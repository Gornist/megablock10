package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/** Кто вызывает: роль из `hello` и имя клиента; `role/client` — пространство имён `rid` (протокол, раздел 3 и 6). */
enum class Role { WORLD, MASTER, TEST, BRIDGE }

data class Caller(val role: Role, val client: String) {
    val namespace: String get() = "${role.name.lowercase()}/$client"
}

/** Куда деть предмет при `run.finish`. */
enum class MoveTo { PHONE, NODE, BURNED }

data class Move(val item: String, val to: MoveTo)

/** Карточка Handover, которую нужно отправить на телефон: предмет ([item]) или эдди ([item] = null, [eddies] > 0). */
data class IssuedTransfer(val runner: String, val item: String?, val eddies: Long, val transfer: String)

/**
 * Заглушка выдачи на телефон (M2): вызывается **после** коммита операции, один раз на новые карточки (повтор по `rid` её
 * не вызывает). Если процесс упал между коммитом и вызовом, карточки восстанавливаются по документам: предметы
 * `outbox:*` с `handover = PENDING` и документы `payout` в `PENDING`.
 */
fun interface HandoverGateway {
    fun issued(transfers: List<IssuedTransfer>)
}

/** Ответ операции: [ok] с полями ответа в [body] либо ошибка (`code`, `msg`, при наличии `doc`) — и то и другое сохраняется по `rid`. */
class OpResult(val ok: Boolean, val body: JsonObject, val replayed: Boolean) {
    val code: String? get() = VJ.str(body, "code")
    val doc: JsonObject? get() = body["doc"] as? JsonObject
}

/**
 * Операции с ценностями (протокол, раздел 6) поверх [DocStore.transaction].
 *
 * Правила: каждая операция — одна транзакция (предметы, колода, сессия, узел и запись `rid` меняются вместе или никак);
 * проверки идут до записей, поэтому доменная ошибка (`wrong_owner`, `session_state`, …) не оставляет следов, кроме записи
 * `rid`; исключение посреди операции откатывает всё. Повтор `rid` с теми же параметрами возвращает сохранённый ответ,
 * с другими — `rid_mismatch`. Сам [DocStore] не меняется: записи `rid` — документы типа [RID_TYPE].
 *
 * Мост не создаёт и не уничтожает предметы, кроме [submitDeck] (там предметы уже есть в `inbox`) — только меняет `owner`.
 */
@Suppress("TooManyFunctions")
class ValueOps(
    private val store: DocStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val gateway: HandoverGateway = HandoverGateway { },
) {
    /** Доменная ошибка: бросается до записей (кроме возврата входа), сохраняется как ответ по `rid`. */
    private class Fail(val code: String, message: String, val doc: Doc? = null) : Exception(message)

    private class Ctx {
        val issued = ArrayList<IssuedTransfer>()
        var alerts = 0
    }

    private fun fail(code: String, msg: String, doc: Doc? = null): Nothing = throw Fail(code, msg, doc)

    // ---------- 6.1 сдать деку ----------

    fun submitDeck(
        caller: Caller,
        rid: String,
        runner: String,
        callsign: String,
        terminal: String,
        items: List<String>,
        protectedItem: String,
    ): OpResult {
        if (runner.isEmpty() || !validDeck(items, protectedItem)) {
            throw StoreException("bad_request", "дека пуста, с повторами или защищённого нет в ней")
        }
        val params = VJ.obj(
            "op" to VJ.p("submit_deck"), "runner" to VJ.p(runner), "callsign" to VJ.p(callsign),
            "terminal" to VJ.p(terminal), "items" to VJ.arr(items), "protected" to VJ.p(protectedItem),
        )
        return execute(caller, "submit_deck", rid, params) { tx, ctx ->
            val docs = items.map { tx.get(ITEM, it) ?: throw StoreException("not_found", "предмета $it нет") }
            val nodeId = try {
                checkSubmit(tx, runner, terminal, docs)
            } catch (f: Fail) {
                // Отказ: предметы остаются в inbox, Мост сам выдаёт их обратно в этой же транзакции.
                val refundRid = "refund:" + rid.removePrefix("enter:")
                val refundParams = VJ.obj("op" to VJ.p("refund"), "of" to VJ.p(rid))
                exec(tx, caller, refundRid, refundParams) {
                    val own = docs.filter { VJ.str(it.data, "owner") == "inbox:$runner" }
                    issueItems(tx, ctx, caller, refundRid, runner, own, 0L)
                }
                throw f
            }
            doSubmit(tx, caller, rid, runner, callsign, terminal, nodeId, docs, protectedItem)
        }
    }

    private fun validDeck(items: List<String>, protectedItem: String): Boolean =
        items.isNotEmpty() && items.toSet().size == items.size && protectedItem in items

    private fun validIssue(items: List<String>, eddies: Long): Boolean =
        items.toSet().size == items.size && eddies >= 0 && (items.isNotEmpty() || eddies > 0)

    /** Все проверки входа, включая выбор узла (учебный или терминала); возвращает узел сессии. Любой отказ ведёт к возврату. */
    private fun checkSubmit(tx: DocStore.Tx, runner: String, terminal: String, docs: List<Doc>): String {
        for (d in docs) {
            if (VJ.str(d.data, "owner") != "inbox:$runner") fail("wrong_owner", "${d.id} не в inbox игрока", d)
        }
        val rd = tx.get(RUNNER, runnerDocId(runner))
        if (rd != null && VJ.bool(rd.data, "blocked")) fail("session_state", "нетраннер заблокирован")
        val open = store.list(SESSION).filter { VJ.str(it.data, "state") != "closed" }
        if (open.any { VJ.str(it.data, "runner") == runner }) fail("session_state", "у игрока уже есть открытая сессия")
        val term = tx.get(TERMINAL, terminal) ?: fail("session_state", "терминала нет")
        if (open.any { VJ.str(it.data, "terminal") == terminal }) fail("session_state", "терминал занят")
        val termNode = VJ.str(term.data, "node") ?: fail("session_state", "у терминала нет узла")
        val nd = tx.get(NODE, termNode) ?: fail("session_state", "узла терминала нет")
        if (VJ.lng(nd.data, "lockdown_until") > clock()) fail("session_state", "узел в локдауне")
        val tutorialDone = rd != null && VJ.bool(rd.data, "tutorial_done")
        if (tutorialDone) return termNode
        val tutorial = VJ.str(tx.get(SETTINGS, "global")?.data ?: VJ.obj(), "tutorial_node") ?: "node_00"
        val tn = tx.get(NODE, tutorial) ?: fail("session_state", "учебного узла $tutorial нет")
        if (VJ.lng(tn.data, "lockdown_until") > clock()) fail("session_state", "учебный узел в локдауне")
        return tutorial
    }

    @Suppress("LongParameterList")
    private fun doSubmit(
        tx: DocStore.Tx,
        caller: Caller,
        rid: String,
        runner: String,
        callsign: String,
        terminal: String,
        nodeId: String,
        docs: List<Doc>,
        protectedItem: String,
    ): JsonObject {
        val rd = tx.get(RUNNER, runnerDocId(runner))
        val now = clock()
        val sid = "s_" + VJ.sha256Hex("${caller.namespace}|$rid").take(16)
        tx.put(
            SESSION, sid, 0,
            VJ.obj(
                "state" to VJ.p("pending"), "terminal" to VJ.p(terminal), "node" to VJ.p(nodeId),
                "runner" to VJ.p(runner), "callsign" to VJ.p(callsign), "enter_rid" to VJ.p(rid.removePrefix("enter:")),
                "confirmed_at" to VJ.p(0L), "loot_eddies" to VJ.p(0L), "outcome" to JsonNull, "finished_at" to VJ.p(0L),
                "world" to VJ.obj("connected" to VJ.p(false), "trace" to VJ.p(0L)),
            ),
        )
        tx.put(DECK, sid, 0, VJ.obj("items" to VJ.arr(docs.map { it.id }), "protected" to VJ.p(protectedItem)))
        for (d in docs) {
            tx.put(
                ITEM, d.id, d.ver,
                VJ.with(d.data, "owner" to VJ.p("deck:$sid"), "protected" to VJ.p(d.id == protectedItem)),
            )
        }
        if (rd == null) {
            tx.put(RUNNER, runnerDocId(runner), 0, newRunner(runner, callsign))
        } else {
            tx.put(RUNNER, rd.id, rd.ver, VJ.with(rd.data, "callsign" to VJ.p(callsign)))
        }
        return VJ.obj("session" to VJ.p(sid), "state" to VJ.p("pending"), "at" to VJ.p(now))
    }

    // ---------- 6.2 взять из узла ----------

    /** Взять предмет [item] или (если [item] = null) [eddies] эдди из запаса узла в деку/добычу сессии. */
    fun takeFromNode(caller: Caller, rid: String, session: String, node: String, item: String?, eddies: Long = 0): OpResult {
        if ((item == null) == (eddies <= 0L)) throw StoreException("bad_request", "нужен ровно один из item и eddies > 0")
        val params = VJ.obj(
            "op" to VJ.p("take_from_node"), "session" to VJ.p(session), "node" to VJ.p(node),
            "item" to VJ.p(item), "eddies" to VJ.p(eddies),
        )
        return execute(caller, "take_from_node", rid, params) { tx, _ ->
            val s = activeSession(tx, session, node)
            val nd = tx.get(NODE, node) ?: throw StoreException("not_found", "узла нет")
            if (item == null) {
                val have = VJ.lng(nd.data, "eddies")
                if (have < eddies) fail("wrong_owner", "в узле эдди $have, а нужно $eddies", nd)
                tx.put(NODE, nd.id, nd.ver, VJ.with(nd.data, "eddies" to VJ.p(have - eddies)))
                val loot = VJ.lng(s.data, "loot_eddies") + eddies
                tx.put(SESSION, s.id, s.ver, VJ.with(s.data, "loot_eddies" to VJ.p(loot)))
                VJ.obj("eddies" to VJ.p(eddies))
            } else {
                val it = tx.get(ITEM, item) ?: throw StoreException("not_found", "предмета нет")
                if (VJ.str(it.data, "owner") != "node:$node") fail("wrong_owner", "предмет не в узле", it)
                val deck = loadDeck(tx, session)
                val moved = tx.put(ITEM, it.id, it.ver, VJ.with(it.data, "owner" to VJ.p("deck:$session")))
                putDeckItems(tx, deck, (deckItems(deck) + item).distinct())
                VJ.obj("item" to VJ.docJson(moved))
            }
        }
    }

    // ---------- 6.3 оставить в узле ----------

    fun leaveInNode(caller: Caller, rid: String, session: String, node: String, item: String): OpResult {
        val params = VJ.obj(
            "op" to VJ.p("leave_in_node"), "session" to VJ.p(session), "node" to VJ.p(node), "item" to VJ.p(item),
        )
        return execute(caller, "leave_in_node", rid, params) { tx, _ ->
            val s = loadSession(tx, session)
            if (VJ.str(s.data, "state") == "closed") fail("session_state", "сессия закрыта", s)
            if (VJ.str(s.data, "node") != node) throw StoreException("bad_request", "узел не тот")
            if (tx.get(NODE, node) == null) throw StoreException("not_found", "узла нет")
            val it = tx.get(ITEM, item) ?: throw StoreException("not_found", "предмета нет")
            if (VJ.str(it.data, "owner") != "deck:$session") fail("wrong_owner", "предмет не в деке сессии", it)
            if (VJ.bool(it.data, "protected")) fail("protected_item", "защищённого демона можно только на телефон", it)
            val deck = loadDeck(tx, session)
            val moved = tx.put(ITEM, it.id, it.ver, VJ.with(it.data, "owner" to VJ.p("node:$node")))
            putDeckItems(tx, deck, deckItems(deck) - item)
            VJ.obj("item" to VJ.docJson(moved))
        }
    }

    // ---------- 6.4 выдать на телефон ----------

    /**
     * Выдать [items] и [eddies] на телефон [runner]. Источник предмета: `inbox:<runner>`, колода сессии этого игрока,
     * а из узла — только вызов мастера (ручная выдача). Эдди «из воздуха» (эмиссия) может выдавать мастер, не сервер мира;
     * эдди забега выплачивает только [finishRun].
     */
    fun issueToPhone(caller: Caller, rid: String, runner: String, items: List<String>, eddies: Long, reason: String): OpResult {
        if (runner.isEmpty() || !validIssue(items, eddies)) {
            throw StoreException("bad_request", "нужны предметы или эдди, без повторов")
        }
        val params = VJ.obj(
            "op" to VJ.p("issue_to_phone"), "runner" to VJ.p(runner), "items" to VJ.arr(items),
            "eddies" to VJ.p(eddies), "reason" to VJ.p(reason),
        )
        if (eddies > 0 && caller.role == Role.WORLD) throw StoreException("forbidden", "эмиссию эдди выдаёт мастер")
        return execute(caller, "issue_to_phone", rid, params) { tx, ctx ->
            val docs = items.map { tx.get(ITEM, it) ?: throw StoreException("not_found", "предмета $it нет") }
            issueItems(tx, ctx, caller, rid, runner, docs, eddies)
        }
    }

    /** Общая часть выдачи: проверки источников, затем записи. Колоды уменьшаются, предметы уходят в `outbox`. */
    private fun issueItems(
        tx: DocStore.Tx,
        ctx: Ctx,
        caller: Caller,
        rid: String,
        runner: String,
        docs: List<Doc>,
        eddies: Long,
    ): JsonObject {
        val decks = LinkedHashSet<String>()
        for (d in docs) {
            val owner = VJ.str(d.data, "owner") ?: ""
            when {
                owner == "inbox:$runner" -> Unit
                owner.startsWith("deck:") -> {
                    val sid = owner.removePrefix("deck:")
                    val s = tx.get(SESSION, sid)
                    if (s == null || VJ.str(s.data, "runner") != runner || VJ.str(s.data, "state") == "closed") {
                        fail("wrong_owner", "${d.id} не в деке этого игрока", d)
                    }
                    decks.add(sid)
                }
                owner.startsWith("node:") && (caller.role == Role.MASTER || caller.role == Role.TEST) -> Unit
                else -> fail("wrong_owner", "${d.id} сейчас у $owner", d)
            }
            checkProtectedDestination(d, runner)
        }
        val ns = caller.namespace
        val transfers = docs.map { d -> d.id to toOutbox(tx, ctx, ns, rid, runner, d) }
        for (sid in decks) {
            val deck = loadDeck(tx, sid)
            val gone = docs.filter { VJ.str(it.data, "owner") == "deck:$sid" }.map { it.id }.toSet()
            putDeckItems(tx, deck, deckItems(deck).filterNot { it in gone })
        }
        val eddiesTransfer = if (eddies > 0) payout(tx, ctx, ns, rid, runner, eddies) else null
        return VJ.obj(
            "transfers" to JsonArray(transfers.map { (i, t) -> VJ.obj("item" to VJ.p(i), "transfer" to VJ.p(t)) }),
            "eddies_transfer" to VJ.p(eddiesTransfer),
        )
    }

    /** Защищённый демон уходит только своему хозяину (`origin = phone:<ключ>`). */
    private fun checkProtectedDestination(d: Doc, runner: String) {
        if (VJ.bool(d.data, "protected") && VJ.str(d.data, "origin") != "phone:$runner") {
            fail("protected_item", "защищённый демон — только своему игроку", d)
        }
    }

    private fun toOutbox(tx: DocStore.Tx, ctx: Ctx, ns: String, rid: String, runner: String, d: Doc): String {
        val tid = "tr_" + VJ.sha256Hex("$ns|$rid|${d.id}").take(12)
        tx.put(
            ITEM, d.id, d.ver,
            VJ.with(d.data, "owner" to VJ.p("outbox:$runner"), "handover" to VJ.p("PENDING"), "out_transfer" to VJ.p(tid)),
        )
        ctx.issued.add(IssuedTransfer(runner, d.id, 0L, tid))
        return tid
    }

    /** Эдди на телефон — документ `payout` (ожидает денежной карточки M2); без него потеря карточки потеряла бы эдди. */
    private fun payout(tx: DocStore.Tx, ctx: Ctx, ns: String, rid: String, runner: String, eddies: Long): String {
        val tid = "tr_" + VJ.sha256Hex("$ns|$rid|eddies").take(12)
        tx.put(
            PAYOUT, tid, 0,
            VJ.obj("runner" to VJ.p(runner), "eddies" to VJ.p(eddies), "state" to VJ.p("PENDING"), "rid" to VJ.p(rid)),
        )
        ctx.issued.add(IssuedTransfer(runner, null, eddies, tid))
        return tid
    }

    // ---------- 6.5 исход забега ----------

    fun finishRun(
        caller: Caller,
        rid: String,
        session: String,
        outcome: String,
        node: String,
        disconnect: Boolean,
        moves: List<Move>,
    ): OpResult {
        if (outcome !in FINISH_OUTCOMES) throw StoreException("bad_request", "неизвестный исход $outcome")
        val params = VJ.obj(
            "op" to VJ.p("run.finish"), "session" to VJ.p(session), "outcome" to VJ.p(outcome), "node" to VJ.p(node),
            "disconnect" to VJ.p(disconnect),
            "moves" to JsonArray(moves.map { VJ.obj("item" to VJ.p(it.item), "to" to VJ.p(it.to.name.lowercase())) }),
        )
        return execute(caller, "run.finish", rid, params) { tx, ctx -> doFinish(tx, ctx, caller, rid, session, outcome, node, disconnect, moves) }
    }

    @Suppress("LongParameterList", "LongMethod")
    private fun doFinish(
        tx: DocStore.Tx,
        ctx: Ctx,
        caller: Caller,
        rid: String,
        session: String,
        outcome: String,
        node: String,
        disconnect: Boolean,
        moves: List<Move>,
    ): JsonObject {
        val s = activeSession(tx, session, node)
        val nd = tx.get(NODE, node) ?: throw StoreException("not_found", "узла нет")
        val deckDocs = ownedBy(tx, "deck:$session")
        val plan = planMoves(tx, deckDocs, moves, outcome)
        val runner = VJ.str(s.data, "runner") ?: throw StoreException("internal", "у сессии нет игрока")
        val ns = caller.namespace
        val transfers = ArrayList<Pair<String, String>>()
        for ((d, to) in plan) {
            when (to) {
                MoveTo.PHONE -> transfers.add(d.id to toOutbox(tx, ctx, ns, rid, runner, d))
                MoveTo.NODE -> tx.put(ITEM, d.id, d.ver, VJ.with(d.data, "owner" to VJ.p("node:$node")))
                MoveTo.BURNED -> tx.put(ITEM, d.id, d.ver, VJ.with(d.data, "owner" to VJ.p("burned:$session")))
            }
        }
        val deck = loadDeck(tx, session)
        putDeckItems(tx, deck, emptyList())

        val loot = VJ.lng(s.data, "loot_eddies")
        val now = clock()
        val settings = tx.get(SETTINGS, "global")?.data ?: VJ.obj()
        var nodeData = nd.data
        var eddiesTransfer: String? = null
        var paid = 0L
        if (loot > 0 && outcome == "clean") {
            eddiesTransfer = payout(tx, ctx, ns, rid, runner, loot)
            paid = loot
        } else if (loot > 0) {
            nodeData = VJ.with(nodeData, "eddies" to VJ.p(VJ.lng(nodeData, "eddies") + loot))
        }
        if (outcome == "soft_ice") {
            val pause = settings["soft_ice_reentry_pause_s"]?.let { VJ.lng(settings, "soft_ice_reentry_pause_s") } ?: DEFAULT_PAUSE_S
            nodeData = VJ.with(nodeData, "lockdown_until" to VJ.p(now + pause * MS))
        }
        if (nodeData != nd.data) tx.put(NODE, nd.id, nd.ver, nodeData)

        updateRunnerAfterFinish(tx, ctx, s, outcome, disconnect, node)
        val closed = tx.put(
            SESSION, s.id, s.ver,
            VJ.with(
                s.data, "state" to VJ.p("closed"), "outcome" to VJ.p(outcome), "finished_at" to VJ.p(now),
                "loot_eddies" to VJ.p(0L), "eddies_paid" to VJ.p(paid), "disconnect" to VJ.p(disconnect),
            ),
        )
        return VJ.obj(
            "session" to VJ.docJson(closed),
            "transfers" to JsonArray(transfers.map { (i, t) -> VJ.obj("item" to VJ.p(i), "transfer" to VJ.p(t)) }),
            "eddies_transfer" to VJ.p(eddiesTransfer),
        )
    }

    /** Проверка `moves` по таблице исходов; защищённый демон всегда на телефон (Мост добавляет его сам). */
    private fun planMoves(tx: DocStore.Tx, deck: List<Doc>, moves: List<Move>, outcome: String): List<Pair<Doc, MoveTo>> {
        val inDeck = deck.associateBy { it.id }
        if (moves.map { it.item }.toSet().size != moves.size) throw StoreException("bad_request", "предмет в moves дважды")
        val target = HashMap<String, MoveTo>()
        for (m in moves) {
            val d = inDeck[m.item]
            if (d == null) {
                val other = tx.get(ITEM, m.item) ?: throw StoreException("not_found", "предмета ${m.item} нет")
                fail("wrong_owner", "${m.item} не в деке сессии", other)
            }
            if (VJ.bool(d.data, "protected") && m.to != MoveTo.PHONE) fail("protected_item", "защищённый — только на телефон", d)
            target[m.item] = m.to
        }
        val plan = ArrayList<Pair<Doc, MoveTo>>()
        for (d in deck) {
            val isProtected = VJ.bool(d.data, "protected")
            val to = target[d.id] ?: if (isProtected) MoveTo.PHONE else throw StoreException("bad_request", "${d.id} не упомянут в moves")
            val loot = (VJ.str(d.data, "origin") ?: "").startsWith("node:")
            if (!isProtected && to !in allowedTargets(outcome, loot)) {
                throw StoreException("bad_request", "${d.id}: при исходе $outcome нельзя в ${to.name.lowercase()}")
            }
            plan.add(d to to)
        }
        return plan
    }

    private fun allowedTargets(outcome: String, loot: Boolean): Set<MoveTo> = when {
        loot -> if (outcome == "clean") setOf(MoveTo.PHONE) else setOf(MoveTo.NODE)
        outcome == "black_ice" -> setOf(MoveTo.NODE)
        outcome == "emergency" -> setOf(MoveTo.PHONE, MoveTo.BURNED)
        else -> setOf(MoveTo.PHONE)
    }

    private fun updateRunnerAfterFinish(tx: DocStore.Tx, ctx: Ctx, s: Doc, outcome: String, disconnect: Boolean, node: String) {
        val key = VJ.str(s.data, "runner")!!
        val cur = tx.get(RUNNER, runnerDocId(key))
        val base = cur?.data ?: newRunner(key, VJ.str(s.data, "callsign") ?: "")
        var next = VJ.with(base, "runs" to VJ.p(VJ.lng(base, "runs") + 1), "tutorial_done" to VJ.p(true))
        if (outcome == "black_ice") {
            next = VJ.with(next, "blocked" to VJ.p(true), "blocked_reason" to VJ.p("флэтлайн, сессия ${s.id}"))
            val cause = if (disconnect) "обрыв до флэтлайна" else "флэтлайн"
            val msg = "ФЛЭТЛАЙН ($cause): ${VJ.str(s.data, "callsign")}, узел $node, терминал ${VJ.str(s.data, "terminal")}, сессия ${s.id}"
            val id = "al_${store.seq + 1}_${ctx.alerts++}"
            tx.put(ALERT, id, 0, VJ.obj("kind" to VJ.p("flatline"), "msg" to VJ.p(msg), "items" to VJ.arr(emptyList())))
        }
        if (cur == null) tx.put(RUNNER, runnerDocId(key), 0, next) else tx.put(RUNNER, cur.id, cur.ver, next)
    }

    // ---------- сессия: отмена ----------

    /** `session.abort`: только из `pending`; вся дека (и защищённый демон) уходит на телефон, rid выдачи — `abort:<сессия>`. */
    fun abortSession(caller: Caller, session: String, reason: String): OpResult {
        val rid = "abort:$session"
        val params = VJ.obj("op" to VJ.p("session.abort"), "session" to VJ.p(session), "reason" to VJ.p(reason))
        return execute(caller, "session.abort", rid, params) { tx, ctx ->
            val s = loadSession(tx, session)
            if (VJ.str(s.data, "state") == "closed" && VJ.str(s.data, "outcome") == "aborted") {
                return@execute VJ.obj("session" to VJ.docJson(s))
            }
            if (VJ.str(s.data, "state") != "pending") fail("session_state", "отменить можно только pending", s)
            val runner = VJ.str(s.data, "runner")!!
            val docs = ownedBy(tx, "deck:$session")
            issueItems(tx, ctx, caller, rid, runner, docs, 0L)
            val closed = tx.put(
                SESSION, s.id, s.ver,
                VJ.with(s.data, "state" to VJ.p("closed"), "outcome" to VJ.p("aborted"), "finished_at" to VJ.p(clock())),
            )
            VJ.obj("session" to VJ.docJson(closed))
        }
    }

    // ---------- каркас: права, rid, транзакция ----------

    private fun requireAllowed(caller: Caller, op: String) {
        val ok = when (op) {
            "submit_deck" -> caller.role == Role.TEST || caller.role == Role.BRIDGE
            "take_from_node", "leave_in_node", "run.finish" -> caller.role != Role.BRIDGE
            else -> true
        }
        if (!ok) throw StoreException("forbidden", "роль ${caller.role} не может $op")
    }

    private fun execute(caller: Caller, op: String, rid: String, params: JsonObject, body: (DocStore.Tx, Ctx) -> JsonObject): OpResult {
        requireAllowed(caller, op)
        if (rid.isEmpty() || rid.length > MAX_RID) throw StoreException("bad_request", "rid от 1 до $MAX_RID символов")
        val ctx = Ctx()
        val result = store.transaction { tx -> exec(tx, caller, rid, params) { body(tx, ctx) } }
        if (ctx.issued.isNotEmpty()) notifyGateway(ctx.issued)
        return result
    }

    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    private fun notifyGateway(list: List<IssuedTransfer>) {
        try {
            gateway.issued(list)
        } catch (e: Exception) {
            // Сбой доставки не отменяет коммит: карточки восстановит сверка M2 по PENDING-документам.
        }
    }

    private fun exec(tx: DocStore.Tx, caller: Caller, rid: String, params: JsonObject, body: () -> JsonObject): OpResult {
        val ns = caller.namespace
        val key = VJ.sha256Hex("$ns|$rid")
        val sig = params.toString()
        val rec = tx.get(RID_TYPE, key)
        if (rec != null) {
            if (VJ.str(rec.data, "params") != sig) throw StoreException("rid_mismatch", "rid $rid уже использован с другими параметрами")
            val resp = rec.data["response"] as JsonObject
            return OpResult(VJ.bool(resp, "ok"), resp["body"] as JsonObject, true)
        }
        val result = try {
            OpResult(true, body(), false)
        } catch (f: Fail) {
            val err = VJ.obj("code" to VJ.p(f.code), "msg" to VJ.p(f.message), "doc" to (f.doc?.let { VJ.docJson(it) } ?: JsonNull))
            OpResult(false, err, false)
        }
        tx.put(
            RID_TYPE, key, 0,
            VJ.obj(
                "rid" to VJ.p(rid), "ns" to VJ.p(ns), "params" to VJ.p(sig), "at" to VJ.p(clock()),
                "response" to VJ.obj("ok" to VJ.p(result.ok), "body" to result.body),
            ),
        )
        return result
    }

    // ---------- чтение ----------

    private fun loadSession(tx: DocStore.Tx, id: String): Doc = tx.get(SESSION, id) ?: throw StoreException("not_found", "сессии нет")

    private fun activeSession(tx: DocStore.Tx, id: String, node: String): Doc {
        val s = loadSession(tx, id)
        if (VJ.str(s.data, "state") != "active") fail("session_state", "сессия не active", s)
        if (VJ.str(s.data, "node") != node) throw StoreException("bad_request", "узел не тот")
        return s
    }

    private fun loadDeck(tx: DocStore.Tx, sid: String): Doc =
        tx.get(DECK, sid) ?: throw StoreException("internal", "у сессии $sid нет деки")

    private fun deckItems(deck: Doc): List<String> = VJ.list(deck.data, "items")

    private fun putDeckItems(tx: DocStore.Tx, deck: Doc, items: List<String>) {
        tx.put(DECK, deck.id, deck.ver, VJ.with(deck.data, "items" to VJ.arr(items)))
    }

    private fun ownedBy(tx: DocStore.Tx, owner: String): List<Doc> =
        store.list(ITEM).mapNotNull { tx.get(ITEM, it.id) }.filter { VJ.str(it.data, "owner") == owner }

    private fun newRunner(key: String, callsign: String): JsonObject = VJ.obj(
        "key" to VJ.p(key), "callsign" to VJ.p(callsign), "blocked" to VJ.p(false), "blocked_reason" to JsonNull,
        "runs" to VJ.p(0L), "tutorial_done" to VJ.p(false),
    )

    companion object {
        const val RID_TYPE = "op_rid"
        const val ITEM = "item"
        const val DECK = "deck"
        const val SESSION = "session"
        const val NODE = "node"
        const val RUNNER = "runner"
        const val ALERT = "alert"
        const val SETTINGS = "settings"
        const val TERMINAL = "terminal"
        const val PAYOUT = "payout"

        private const val MAX_RID = 128
        private const val MS = 1000L
        private const val DEFAULT_PAUSE_S = 600L
        private val FINISH_OUTCOMES = setOf("clean", "emergency", "soft_ice", "black_ice")

        /**
         * Id документа `runner`. Ключ игрока (X.509 base64url, ~120 символов) длиннее предела id в 64 символа, поэтому
         * id — `r_` + 32 hex от SHA-256 ключа; сам ключ лежит в `data.key`.
         */
        fun runnerDocId(key: String): String = "r_" + VJ.sha256Hex(key).take(32)
    }
}
