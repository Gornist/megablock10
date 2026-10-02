package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Решение мастера по запросу «ждём мастера». */
enum class Decision(val wire: String) {
    APPROVE("approve"), DENY("deny");

    companion object {
        fun parse(s: String?): Decision? = entries.firstOrNull { it.wire == s }
    }
}

/**
 * Итог [MasterOps.gate]: [AUTO] — «ждём мастера» для этого вида выключено, шаг применять сразу; [WAIT] — запрос создан или
 * ещё не решён, шаг не применять; [DECIDED] — запрос решён мастером или по таймауту, [decision] обязательно.
 */
class GateResult(val mode: Mode, val decision: Decision?, val req: Doc?) {
    enum class Mode(val wire: String) { AUTO("auto"), WAIT("wait"), DECIDED("decided") }

    /** Можно ли применять шаг сейчас. */
    val approved: Boolean get() = decision == Decision.APPROVE && mode != Mode.WAIT

    fun toJson(): Map<String, JsonElement> = mapOf(
        "mode" to VJ.p(mode.wire), "decision" to VJ.p(decision?.wire), "req" to (req?.toJson() ?: JsonNull),
    )
}

/**
 * Ручные операции мастера (протокол, раздел 6a; `docs/netrun.md`, «Инструменты мастера»). «Кнопка раньше автоматики»:
 * правила Моста ([MasterRules]) вызывают те же методы, что и сообщения `master.*`.
 *
 * Роль проверяется здесь: `master.*` — [Role.MASTER], [Role.TEST], [Role.BRIDGE] (автоматика); `master.decide` и `master.reply`
 * — без [Role.BRIDGE]: решение за мастера автоматика не принимает, у неё есть таймаут. Каждая операция — одна транзакция.
 * Все они по природе идемпотентны (устанавливают состояние), кроме добавления сообщения в `net_query` — оно дедуплицируется по `mid`.
 *
 * Документы: флаги — `settings/global` (`paused`, `venue_link`), цель и пауза узла — `node_cfg/<узел>` (`goal`, `paused`),
 * запросы — `master_req/<вид>:<ссылка>`, заготовки — `template/<id>`, канал — `net_query/nq_<n>`.
 */
@Suppress("TooManyFunctions")
class MasterOps(private val store: DocStore, private val clock: () -> Long = System::currentTimeMillis) {
    // ---------- пауза Сети ----------

    /**
     * `master.pause`: [node] = null — вся Сеть (`settings/global.paused`), иначе один узел (`node_cfg/<узел>.paused`).
     * Сервер мира читает флаги и замораживает ICE и trace ([isPaused]). При снятии паузы сроки целей сдвигаются на время паузы.
     */
    fun pause(caller: Caller, on: Boolean, node: String?): Map<String, JsonElement> {
        requireMaster(caller, "master.pause")
        return store.transaction { tx ->
            val now = clock()
            if (node == null) {
                val cur = tx.get(SETTINGS, GLOBAL)
                val was = cur != null && VJ.bool(cur.data, "paused")
                val doc = tx.edit(SETTINGS, GLOBAL) { pausedFlags(it, on, was, now) }
                if (was && !on) shiftGoals(tx, cur!!.data, now, tx.list(NODE_CFG).filter { !VJ.bool(it.data, "paused") })
                mapOf("doc" to doc.toJson())
            } else {
                tx.get(NODE, node) ?: throw StoreException("not_found", "узла $node нет")
                val cur = tx.get(NODE_CFG, node)
                val was = cur != null && VJ.bool(cur.data, "paused")
                val doc = tx.edit(NODE_CFG, node) { pausedFlags(it, on, was, now) }
                if (was && !on) shiftGoals(tx, cur!!.data, now, listOf(doc))
                mapOf("doc" to tx.get(NODE_CFG, node)!!.toJson())
            }
        }
    }

    private fun pausedFlags(d: JsonObject, on: Boolean, was: Boolean, now: Long): JsonObject = when {
        on && !was -> VJ.with(d, "paused" to VJ.p(true), "paused_at" to VJ.p(now))
        on -> d
        else -> VJ.with(d, "paused" to VJ.p(false), "paused_at" to VJ.p(0L))
    }

    /** Сдвигает срок активной цели на время паузы, которая только что кончилась (`paused_at` берётся из [pausedData]). */
    private fun shiftGoals(tx: DocStore.Tx, pausedData: JsonObject, now: Long, targets: List<Doc>) {
        val delta = (now - VJ.lng(pausedData, "paused_at")).coerceAtLeast(0L)
        if (delta == 0L) return
        for (t in targets) {
            val cur = tx.get(NODE_CFG, t.id) ?: continue
            val goal = cur.data["goal"] as? JsonObject ?: continue
            if (VJ.bool(goal, "done") || VJ.lng(goal, "deadline") == 0L) continue
            val shifted = VJ.with(goal, "deadline" to VJ.p(VJ.lng(goal, "deadline") + delta))
            tx.put(NODE_CFG, cur.id, cur.ver, VJ.with(cur.data, "goal" to shifted))
        }
    }

    // ---------- рубильник связи с площадкой ----------

    /** `master.link`: `settings/global.venue_link` — быстрые события на точки уходят только при `true` ([venueLinkOn]). */
    fun setVenueLink(caller: Caller, on: Boolean): Map<String, JsonElement> {
        requireMaster(caller, "master.link")
        val doc = store.transaction { tx -> tx.edit(SETTINGS, GLOBAL) { VJ.with(it, "venue_link" to VJ.p(on)) } }
        return mapOf("doc" to doc.toJson())
    }

    // ---------- цели и сроки узла ----------

    /**
     * `master.goal`: узел [node] «к цели [kind] [value] за [inS] секунд» или к абсолютному [deadlineAt]. `open` — открыть узел
     * к сроку (снять локдаун), `lockdown` — закрыть на [value] секунд (по умолчанию как после Soft ICE) через «ждём мастера»;
     * остальные виды (`trace`, `ice` и т. п.) читает сервер мира. Новая цель заменяет прежнюю.
     */
    fun setGoal(caller: Caller, node: String, kind: String, value: Long?, inS: Long?, deadlineAt: Long?): Map<String, JsonElement> {
        requireMaster(caller, "master.goal")
        if (!isValidType(kind)) throw StoreException("bad_request", "kind цели — [a-z_], до 32 символов")
        val now = clock()
        val deadline = when {
            deadlineAt != null && deadlineAt > 0 -> deadlineAt
            inS != null && inS > 0 -> now + inS * MS
            else -> throw StoreException("bad_request", "нужен in_s > 0 или deadline > 0")
        }
        val goal = VJ.obj(
            "kind" to VJ.p(kind), "value" to (value?.let { VJ.p(it) } ?: JsonNull), "deadline" to VJ.p(deadline),
            "set_at" to VJ.p(now), "done" to VJ.p(false), "result" to JsonNull,
        )
        return store.transaction { tx ->
            tx.get(NODE, node) ?: throw StoreException("not_found", "узла $node нет")
            mapOf("doc" to tx.edit(NODE_CFG, node) { VJ.with(it, "goal" to goal) }.toJson())
        }
    }

    /** `master.goal_clear`: убирает цель узла. */
    fun clearGoal(caller: Caller, node: String): Map<String, JsonElement> {
        requireMaster(caller, "master.goal_clear")
        return store.transaction { tx ->
            tx.get(NODE_CFG, node) ?: throw StoreException("not_found", "у узла $node нет настроек")
            mapOf("doc" to tx.edit(NODE_CFG, node) { JsonObject(it - "goal") }.toJson())
        }
    }

    /**
     * Автоматика: применяет созревшие цели `open` и `lockdown` (не для узлов на паузе). Критический шаг `lockdown` идёт через
     * [gate]: пока мастер не решил, цель ждёт. Возвращает число завершённых целей.
     */
    fun applyDueGoals(): Int {
        var done = 0
        for (cfg in store.list(NODE_CFG)) {
            if (store.transaction { tx -> applyGoal(tx, cfg.id) }) done++
        }
        return done
    }

    private fun applyGoal(tx: DocStore.Tx, node: String): Boolean {
        val cfg = tx.get(NODE_CFG, node) ?: return false
        val goal = cfg.data["goal"] as? JsonObject ?: return false
        val now = clock()
        val kind = VJ.str(goal, "kind")
        val due = !VJ.bool(goal, "done") && VJ.lng(goal, "deadline") in 1..now
        if (!due || (kind != "open" && kind != "lockdown") || isPausedIn(tx, node)) return false
        val nodeDoc = tx.get(NODE, node) ?: return finishGoal(tx, cfg, goal, "no_node")
        var result = "applied"
        if (kind == "open") {
            setLockdown(tx, nodeDoc, 0L)
        } else {
            val g = gateIn(tx, "lockdown", "$node.${VJ.lng(goal, "set_at")}", node, "локдаун узла $node по цели мастера")
            if (g.mode == GateResult.Mode.WAIT) return false
            if (g.approved) {
                val secs = goal["value"].long() ?: settingLong(tx, "soft_ice_reentry_pause_s", DEFAULT_LOCKDOWN_S)
                setLockdown(tx, nodeDoc, now + secs * MS)
            } else {
                result = "denied"
            }
        }
        return finishGoal(tx, cfg, goal, result)
    }

    private fun setLockdown(tx: DocStore.Tx, nd: Doc, until: Long) {
        val next = VJ.with(nd.data, "lockdown_until" to VJ.p(until))
        WriteGuard.checkValues(NODE, nd, next)
        if (next != nd.data) tx.put(NODE, nd.id, nd.ver, next)
    }

    private fun finishGoal(tx: DocStore.Tx, cfg: Doc, goal: JsonObject, result: String): Boolean {
        val done = VJ.with(goal, "done" to VJ.p(true), "result" to VJ.p(result), "done_at" to VJ.p(clock()))
        tx.put(NODE_CFG, cfg.id, cfg.ver, VJ.with(cfg.data, "goal" to done))
        return true
    }

    // ---------- «ждём мастера» ----------

    /**
     * `master.gate`: критический шаг (`flatline`, `lockdown`, `nightmare`…) спрашивает, можно ли применять исход самому.
     * Если в настройках `await_<kind>` ≠ 1 — [GateResult.Mode.AUTO]. Иначе по ключу ([kind], [ref]) создаётся документ
     * `master_req` (и тревога `master_request` для панели мастера) и шаг ждёт: решение мастера ([decide]) или таймаут
     * `await_timeout_s` (по умолчанию 60) с действием `await_default_<kind>` (`approve`/`deny`, по умолчанию `approve`).
     * Повторный вызов с тем же ключом возвращает то же решение; новый шаг — новый [ref].
     */
    fun gate(kind: String, ref: String, node: String?, summary: String): Map<String, JsonElement> {
        return store.transaction { tx -> gateIn(tx, kind, ref, node, summary).toJson() }
    }

    /** Версия для правил Моста (роль [Role.BRIDGE]). */
    fun gateForRule(kind: String, ref: String, node: String?, summary: String): GateResult =
        store.transaction { tx -> gateIn(tx, kind, ref, node, summary) }

    private fun gateIn(tx: DocStore.Tx, kind: String, ref: String, node: String?, summary: String): GateResult {
        val id = "$kind:$ref"
        if (!isValidType(kind) || !isValidId(id)) throw StoreException("bad_request", "kind или ref не годятся для id запроса")
        if (settingLong(tx, "await_$kind", 0L) != 1L) return GateResult(GateResult.Mode.AUTO, Decision.APPROVE, null)
        val now = clock()
        val cur = tx.get(MASTER_REQ, id)
        if (cur == null) {
            val timeout = settingLong(tx, "await_timeout_s", DEFAULT_AWAIT_S)
            val dflt = defaultDecision(tx, kind)
            val data = VJ.obj(
                "kind" to VJ.p(kind), "ref" to VJ.p(ref), "node" to VJ.p(node), "summary" to VJ.p(summary),
                "state" to VJ.p("pending"), "default" to VJ.p(dflt.wire), "expires_at" to VJ.p(now + timeout * MS),
                "decision" to JsonNull, "decided_by" to JsonNull, "decided_at" to VJ.p(0L),
            )
            val doc = tx.put(MASTER_REQ, id, 0, data)
            raiseAlert(tx, "master_request", "Ждём мастера: $summary", emptyList())
            return GateResult(GateResult.Mode.WAIT, null, doc)
        }
        val settled = if (VJ.str(cur.data, "state") == "pending" && now >= VJ.lng(cur.data, "expires_at")) expire(tx, cur) else cur
        val decision = Decision.parse(VJ.str(settled.data, "decision"))
        return if (VJ.str(settled.data, "state") == "decided" && decision != null) {
            GateResult(GateResult.Mode.DECIDED, decision, settled)
        } else {
            GateResult(GateResult.Mode.WAIT, null, settled)
        }
    }

    private fun defaultDecision(tx: DocStore.Tx, kind: String): Decision =
        Decision.parse(tx.get(SETTINGS, GLOBAL)?.data?.let { VJ.str(it, "await_default_$kind") }) ?: Decision.APPROVE

    private fun expire(tx: DocStore.Tx, req: Doc): Doc {
        val d = Decision.parse(VJ.str(req.data, "default")) ?: Decision.APPROVE
        return decideIn(tx, req, d, "timeout")
    }

    private fun decideIn(tx: DocStore.Tx, req: Doc, d: Decision, by: String): Doc = tx.put(
        MASTER_REQ, req.id, req.ver,
        VJ.with(req.data, "state" to VJ.p("decided"), "decision" to VJ.p(d.wire), "decided_by" to VJ.p(by), "decided_at" to VJ.p(clock())),
    )

    /**
     * `master.decide`: решение мастера по запросу [req]. Просроченный запрос уже решён таймаутом: другое решение — `req_state`
     * (с документом в `err.doc`), то же — тот же ответ. Повтор того же решения идемпотентен.
     */
    fun decide(caller: Caller, req: String, decision: Decision): Map<String, JsonElement> {
        requireMaster(caller, "master.decide", allowBridge = false)
        return store.transaction { tx ->
            var cur = tx.get(MASTER_REQ, req) ?: throw StoreException("not_found", "запроса $req нет")
            if (VJ.str(cur.data, "state") == "pending" && clock() >= VJ.lng(cur.data, "expires_at")) cur = expire(tx, cur)
            val doc = if (VJ.str(cur.data, "state") == "pending") {
                decideIn(tx, cur, decision, "master")
            } else if (VJ.str(cur.data, "decision") == decision.wire) {
                cur
            } else {
                throw StoreException("req_state", "запрос уже решён: ${VJ.str(cur.data, "decision")}", cur)
            }
            mapOf("doc" to doc.toJson())
        }
    }

    /** Автоматика: решает по таймауту все просроченные запросы. Возвращает число решённых. */
    fun resolveExpired(): Int = store.transaction { tx ->
        val now = clock()
        var n = 0
        for (r in tx.list(MASTER_REQ)) {
            if (VJ.str(r.data, "state") == "pending" && now >= VJ.lng(r.data, "expires_at")) {
                expire(tx, r)
                n++
            }
        }
        n
    }

    // ---------- заготовки ----------

    /**
     * `master.template_apply`: применяет заготовку `template/<id>` одной транзакцией. `settings` из заготовки сливаются
     * в `settings/global` (`world_pub` не трогается), `node_cfg` — в `node_cfg/<узел>` каждого из [nodes]. Нет узла или
     * заготовки — `not_found`, ничего не записано. Заготовки создаёт мастер обычным `put` (тип `template`).
     */
    fun applyTemplate(caller: Caller, template: String, nodes: List<String>): Map<String, JsonElement> {
        requireMaster(caller, "master.template_apply")
        return store.transaction { tx ->
            val t = tx.get(TEMPLATE, template) ?: throw StoreException("not_found", "заготовки $template нет")
            val settings = (t.data["settings"] as? JsonObject)?.let { JsonObject(it - "world_pub") } ?: JsonObject(emptyMap())
            val cfg = t.data["node_cfg"] as? JsonObject ?: JsonObject(emptyMap())
            if (cfg.isNotEmpty() && nodes.isEmpty()) throw StoreException("bad_request", "в заготовке есть node_cfg — нужен nodes")
            for (n in nodes) tx.get(NODE, n) ?: throw StoreException("not_found", "узла $n нет")
            val applied = VJ.obj("id" to VJ.p(template), "at" to VJ.p(clock()))
            tx.edit(SETTINGS, GLOBAL) { VJ.with(JsonObject(it + settings), "template_applied" to applied) }
            for (n in nodes) tx.edit(NODE_CFG, n) { JsonObject(it + cfg) }
            mapOf("template" to VJ.p(template), "nodes" to VJ.arr(nodes), "settings" to VJ.arr(settings.keys.toList()))
        }
    }

    // ---------- «запрос к Сети» ----------

    /**
     * `net.query`: нетраннер ([from] = "runner": [runner] — ключ или позывной) пишет в Сеть; [query] = null — новый запрос
     * `net_query/nq_<n>` и тревога `net_query`, иначе дописывается в существующий и снова становится `open`. [mid] — id
     * сообщения для дедупликации повтора. Роли: world, test, master.
     */
    fun ask(caller: Caller, query: String?, runner: String, mid: String, text: String): Map<String, JsonElement> {
        if (caller.role == Role.BRIDGE) throw StoreException("forbidden", "роль ${caller.role} не может net.query")
        if (mid.isEmpty() || text.isEmpty() || text.length > MAX_TEXT) throw StoreException("bad_request", "mid и text (≤ $MAX_TEXT) нужны")
        return store.transaction { tx ->
            val now = clock()
            val msg = VJ.obj("mid" to VJ.p(mid), "from" to VJ.p("runner"), "text" to VJ.p(text), "at" to VJ.p(now))
            val cur = query?.let { tx.get(NET_QUERY, it) ?: throw StoreException("not_found", "запроса $it нет") }
            if (cur != null && messagesOf(cur).any { VJ.str(it, "mid") == mid }) return@transaction mapOf("doc" to cur.toJson())
            val doc = if (cur == null) {
                val id = "nq_${store.seq + 1}"
                raiseAlert(tx, "net_query", "Запрос к Сети от $runner: $text", emptyList())
                tx.put(NET_QUERY, id, 0, VJ.obj("runner" to VJ.p(runner), "state" to VJ.p("open"), "messages" to JsonArray(listOf(msg))))
            } else {
                tx.put(
                    NET_QUERY, cur.id, cur.ver,
                    VJ.with(cur.data, "state" to VJ.p("open"), "messages" to JsonArray(messagesOf(cur) + msg)),
                )
            }
            mapOf("doc" to doc.toJson())
        }
    }

    /** `master.reply`: ответ мастера в игру; запрос становится `answered`. */
    fun reply(caller: Caller, query: String, mid: String, text: String): Map<String, JsonElement> {
        requireMaster(caller, "master.reply", allowBridge = false)
        if (mid.isEmpty() || text.isEmpty() || text.length > MAX_TEXT) throw StoreException("bad_request", "mid и text (≤ $MAX_TEXT) нужны")
        return store.transaction { tx ->
            val cur = tx.get(NET_QUERY, query) ?: throw StoreException("not_found", "запроса $query нет")
            if (messagesOf(cur).any { VJ.str(it, "mid") == mid }) return@transaction mapOf("doc" to cur.toJson())
            val msg = VJ.obj("mid" to VJ.p(mid), "from" to VJ.p("master"), "text" to VJ.p(text), "at" to VJ.p(clock()))
            val doc = tx.put(
                NET_QUERY, cur.id, cur.ver,
                VJ.with(cur.data, "state" to VJ.p("answered"), "messages" to JsonArray(messagesOf(cur) + msg)),
            )
            mapOf("doc" to doc.toJson())
        }
    }

    private fun messagesOf(d: Doc): List<JsonObject> = (d.data["messages"] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()

    // ---------- общее ----------

    private fun requireMaster(caller: Caller, op: String, allowBridge: Boolean = true) {
        val ok = caller.role == Role.MASTER || caller.role == Role.TEST || (allowBridge && caller.role == Role.BRIDGE)
        if (!ok) throw StoreException("forbidden", "роль ${caller.role} не может $op")
    }

    private fun raiseAlert(tx: DocStore.Tx, kind: String, msg: String, items: List<String>) {
        tx.put(ALERT, "al_${store.seq + 1}_$kind", 0, VJ.obj("kind" to VJ.p(kind), "msg" to VJ.p(msg), "items" to VJ.arr(items)))
    }

    private fun settingLong(tx: DocStore.Tx, key: String, default: Long): Long {
        val v = tx.get(SETTINGS, GLOBAL)?.data?.get(key).long()
        return v ?: default
    }

    private fun isPausedIn(tx: DocStore.Tx, node: String): Boolean =
        (tx.get(SETTINGS, GLOBAL)?.data?.let { VJ.bool(it, "paused") } ?: false) ||
            (tx.get(NODE_CFG, node)?.data?.let { VJ.bool(it, "paused") } ?: false)

    private fun DocStore.Tx.edit(type: String, id: String, change: (JsonObject) -> JsonObject): Doc {
        val cur = get(type, id)
        val next = change(cur?.data ?: JsonObject(emptyMap()))
        WriteGuard.checkValues(type, cur, next)
        return when {
            cur == null -> put(type, id, 0, next)
            cur.data == next -> cur
            else -> put(type, id, cur.ver, next)
        }
    }

    private fun DocStore.Tx.list(type: String): List<Doc> = store.list(type).mapNotNull { get(type, it.id) }

    companion object {
        const val SETTINGS = ValueOps.SETTINGS
        const val NODE = ValueOps.NODE
        const val ALERT = ValueOps.ALERT
        const val GLOBAL = "global"
        const val NODE_CFG = "node_cfg"
        const val MASTER_REQ = "master_req"
        const val TEMPLATE = "template"
        const val NET_QUERY = "net_query"

        private const val MS = 1000L
        private const val DEFAULT_AWAIT_S = 60L
        private const val DEFAULT_LOCKDOWN_S = 600L
        private const val MAX_TEXT = 2000

        /** Стоит ли пауза: вся Сеть (`settings/global.paused`) или узел (`node_cfg/<узел>.paused`). Читает сервер мира и правила. */
        fun isPaused(store: DocStore, node: String): Boolean =
            (store.get(SETTINGS, GLOBAL)?.data?.let { VJ.bool(it, "paused") } ?: false) ||
                (store.get(NODE_CFG, node)?.data?.let { VJ.bool(it, "paused") } ?: false)

        /** Включена ли связь с площадкой (по умолчанию да): отправитель быстрых событий шлёт только при `true`. */
        fun venueLinkOn(store: DocStore): Boolean =
            store.get(SETTINGS, GLOBAL)?.data?.get("venue_link")?.let { (it as? JsonPrimitive)?.content != "false" } ?: true
    }
}

/** Автоматика мастерских инструментов: те же операции, что и кнопки ([MasterOps]), по таймеру правил. */
class MasterRules(private val engine: RuleEngine, private val ops: MasterOps) {
    fun register() {
        engine.every("master_req_timeout", "master_poll_s", 1) { ops.resolveExpired() }
        engine.every("node_goal", "master_poll_s", 1) { ops.applyDueGoals() }
    }
}
