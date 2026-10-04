package com.megablok10.netrun.bridge

import com.megablok10.rules.AlertPlan
import com.megablok10.rules.BreachConstants
import com.megablok10.rules.BreachOutcome
import com.megablok10.rules.BreachResult
import com.megablok10.rules.Container
import com.megablok10.rules.ContainerEddies
import com.megablok10.rules.Daemon
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.LootSlot
import com.megablok10.rules.LootType
import com.megablok10.rules.RamCapacity
import com.megablok10.rules.SecAlertRules
import com.megablok10.rules.SlotPicker
import com.megablok10.rules.Tier
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.random.Random

/** Запрос `run.breach` (протокол, 6.6): итог попытки взлома, которую сыграл сервер мира. */
data class BreachRequest(
    val session: String,
    val node: String,
    /** Номер попытки (`session.world.breach_n`); `rid` = `breach:<сессия>:<n>`. */
    val n: Long,
    /** Тир сетки, которую играл игрок: `BASE`, `HARD` или `NIGHTMARE`. */
    val tier: String,
    /** Рабочие демоны, выбранные во взлом. */
    val selected: List<String>,
    /** Совпавшие, подмножество [selected]. */
    val matched: List<String>,
    /** Эффекты активных окон заряженных демонов к концу попытки: `GHOST`, `TIMESKEW`, `BLACKOUT`. */
    val active: List<String>,
    /** Предметы, лежащие сейчас в хранилищах узла, хранилище панели первым. */
    val vaults: List<String>,
    /** На сколько секунд открыть хранилище, 1..600. */
    val openS: Long,
)

/**
 * `run.breach` — итог взлома хранилища (протокол, 6.6). Сервер мира считает сетку, ходы и совпадения; Мост по итогу считает
 * ценности и последствия функциями `:rules` и пишет их **одной транзакцией**: эдди из запаса узла в добычу сессии, открытые
 * хранилища в `session.opened`, остывание узла в `runner.breach_cooldown`, решённый сигнал СБ документом `sec_alert` и итог
 * в `session.breach`. Предметы хранилищ владельца не меняют — их берёт рука (`op.take_from_node`).
 *
 * Идемпотентность — по `rid` ([ValueOps.execute]); эдди разыгрываются зерном от `rid`, поэтому сумма детерминирована.
 */
fun ValueOps.runBreach(caller: Caller, rid: String, q: BreachRequest): OpResult {
    val tier = BreachCheck.validate(q)
    val params = VJ.obj(
        "op" to VJ.p("run.breach"), "session" to VJ.p(q.session), "node" to VJ.p(q.node), "n" to VJ.p(q.n), "tier" to VJ.p(q.tier),
        "selected" to VJ.arr(q.selected), "matched" to VJ.arr(q.matched), "active" to VJ.arr(q.active), "vaults" to VJ.arr(q.vaults),
        "open_s" to VJ.p(q.openS),
    )
    return execute(caller, "run.breach", rid, params) { tx, _ -> BreachTx(this, tx, caller, rid, q, tier).run() }
}

/** Проверки запроса, не требующие документов (все — `bad_request`, не сохраняются по `rid`: ошибка кода сервера мира). */
internal object BreachCheck {
    private const val MAX_OPEN_S = 600L
    private val activeEffects = setOf(DaemonEffect.GHOST, DaemonEffect.TIMESKEW, DaemonEffect.BLACKOUT)

    fun validate(q: BreachRequest): Tier {
        val tier = Tier.entries.firstOrNull { it.name == q.tier } ?: bad("tier: BASE, HARD или NIGHTMARE")
        if (q.session.isEmpty() || q.node.isEmpty()) bad("нужны session и node")
        if (q.n < 1) bad("n — номер попытки, целое от 1")
        if (q.openS !in 1..MAX_OPEN_S) bad("open_s — от 1 до $MAX_OPEN_S секунд")
        if (q.selected.isEmpty()) bad("selected — хотя бы один демон")
        for ((name, list) in listOf("selected" to q.selected, "matched" to q.matched, "active" to q.active, "vaults" to q.vaults)) {
            if (list.toSet().size != list.size) bad("$name без повторов")
        }
        if (!q.selected.containsAll(q.matched)) bad("matched — подмножество selected")
        for (e in q.active) {
            val effect = DaemonEffect.entries.firstOrNull { it.name == e }
            if (effect == null || effect !in activeEffects) bad("active: GHOST, TIMESKEW или BLACKOUT, а не $e")
        }
        return tier
    }

    private fun bad(msg: String): Nothing = throw StoreException("bad_request", msg)
}

/** Одно открытое хранилище: предмет и срок. */
private data class Opened(val item: String, val until: Long)

/** Тело транзакции `run.breach`; порядок шагов — как в протоколе, 6.6 («Что считает Мост»). */
private class BreachTx(
    private val ops: ValueOps,
    private val tx: DocStore.Tx,
    private val caller: Caller,
    private val rid: String,
    private val q: BreachRequest,
    private val tier: Tier,
) {
    private val now = ops.clock()

    fun run(): JsonObject {
        val s = tx.get(ValueOps.SESSION, q.session) ?: throw StoreException("not_found", "сессии нет")
        val nd = tx.get(ValueOps.NODE, q.node) ?: throw StoreException("not_found", "узла нет")
        if (ops.currentNode(s) != q.node) throw StoreException("bad_request", "узел не тот")
        checkSession(s, nd)
        val daemons = selectedDaemons(s)
        val runnerKey = VJ.str(s.data, "runner").orEmpty()
        val runnerId = ValueOps.runnerDocId(runnerKey)
        val runner = tx.get(ValueOps.RUNNER, runnerId)
        val cooldown = runner?.let { breachCooldown(it) }.orEmpty()
        if ((cooldown[q.node] ?: 0L) > now) ops.fail("cooldown", "узел остывает для этого нетраннера", runner)
        logTierMismatch(nd)

        val matchedIds = q.matched.toSet()
        val result = BreachResult(daemons, matchedIds).outcome
        val matchedDaemons = daemons.filter { it.id in matchedIds }
        val effects = LinkedHashSet<DaemonEffect>()
        matchedDaemons.forEach { effects += it.effect }
        q.active.forEach { name -> effects += DaemonEffect.valueOf(name) }

        var eddies = 0L
        var opened = emptyList<Opened>()
        var exhausted = false
        var cooldownUntil = 0L
        if (result != BreachOutcome.FAIL) {
            eddies = rollEddies(nd, matchedDaemons)
            val pick = pickVaults(s, nd, matchedDaemons)
            opened = pick.first
            exhausted = pick.second
            cooldownUntil = now + cooldownMs()
        }
        val plan = decideAlert(s, nd, runner, result, effects)
        val alert = plan?.let { writeAlert(s, nd, it) }
        writeNode(nd, eddies)
        val lootTotal = writeSession(s, result, effects, eddies, opened, exhausted, alert)
        if (result != BreachOutcome.FAIL) writeRunner(runner, runnerKey, s, cooldown, cooldownUntil)
        return response(result, effects, eddies, lootTotal, opened, exhausted, cooldownUntil, alert)
    }

    // ---------- проверки ----------

    /** `session_state` (сохраняется по `rid`): не `active`, идёт исход, устаревшая попытка, учебный узел. */
    private fun checkSession(s: Doc, nd: Doc) {
        if (VJ.str(s.data, "state") != "active") ops.fail("session_state", "сессия не active", s)
        val finish = (s.data["world"] as? JsonObject)?.get("finish")
        val finishing = finish != null && finish !is JsonNull && !(finish is JsonPrimitive && finish.content.isEmpty())
        if (finishing) ops.fail("session_state", "у сессии идёт исход", s)
        val last = (s.data["breach"] as? JsonObject)?.let { VJ.lng(it, "n") } ?: 0L
        if (q.n <= last) ops.fail("session_state", "попытка ${q.n} устарела, записана $last", s)
        val tutorial = VJ.str(tx.get(ValueOps.SETTINGS, "global")?.data ?: VJ.obj(), "tutorial_node") ?: "node_00"
        if (VJ.bool(nd.data, "tutorial") || nd.id == tutorial) ops.fail("session_state", "учебный узел взлом через Мост не считает", s)
    }

    /** Демоны из `selected`: рабочие демоны этой сессии, цепочки которых помещаются в RAM (иначе `bad_request`). */
    private fun selectedDaemons(s: Doc): List<Daemon> {
        val out = q.selected.map { id ->
            val item = tx.get(ValueOps.ITEM, id) ?: throw StoreException("bad_request", "предмета $id нет")
            val daemon = ItemFacts.daemon(item)
            if (VJ.str(item.data, "owner") != "deck:${q.session}" || daemon == null || !ItemFacts.isWorking(s, item)) {
                throw StoreException("bad_request", "$id — не рабочий демон этой сессии")
            }
            daemon
        }
        val ram = s.data["ram"]?.let { VJ.lng(s.data, "ram") }?.toInt() ?: RamCapacity.DEFAULT
        if (out.sumOf { it.sequence.size } > ram) throw StoreException("bad_request", "цепочки демонов не помещаются в RAM $ram")
        return out
    }

    private fun logTierMismatch(nd: Doc) {
        val nodeTier = Tier.entries.firstOrNull { it.name == VJ.str(nd.data, "tier") }
        if (nodeTier != null && nodeTier != tier) {
            ops.log("breach.tier_mismatch session=${q.session} node=${q.node} played=${tier.name} node_tier=${nodeTier.name}")
        }
    }

    // ---------- эдди и хранилища ----------

    /** Зерно детерминировано от `<namespace>|<rid>`: разбор журнала и тесты получают ту же сумму. */
    private fun random(): Random = Random(java.lang.Long.parseUnsignedLong(VJ.sha256Hex("${caller.namespace}|$rid").take(SEED_HEX), HEX))

    /** Эдди за взлом: бросок по тиру плюс бонус MINER среди совпавших, не больше запаса узла. */
    private fun rollEddies(nd: Doc, matched: List<Daemon>): Long {
        val miner = if (matched.any { it.effect == DaemonEffect.MINER }) ContainerEddies.minerBonus(tier) else 0L
        return minOf(ContainerEddies.roll(tier, random()) + miner, VJ.lng(nd.data, "eddies")).coerceAtLeast(0L)
    }

    /**
     * Остывание узла: `settings/global.breach_cooldown_s` (по умолчанию 30 мин), но не меньше `open_s` попытки — иначе игрок успел бы
     * взломать узел снова, пока открыто прежнее хранилище (протокол, 6.6, п. 5).
     */
    private fun cooldownMs(): Long {
        val settings = tx.get(ValueOps.SETTINGS, "global")?.data
        val sec = settings?.get("breach_cooldown_s")?.let { VJ.lng(settings, "breach_cooldown_s") }
            ?: (BreachConstants.CONTAINER_COOLDOWN_MINUTES * SEC_PER_MIN)
        return maxOf(sec, q.openS) * MS
    }

    /**
     * Какие хранилища открыть: для каждого совпавшего EXTRACT-демона (в порядке `selected`) первое подходящее по
     * [SlotPicker.pickSlot]; нет подходящего — `exhausted`. Предмет, уже не лежащий в узле, пропускается без ошибки.
     */
    private fun pickVaults(s: Doc, nd: Doc, matched: List<Daemon>): Pair<List<Opened>, Boolean> {
        val extractors = matched.filter { it.effect == DaemonEffect.EXTRACT_SHARD || it.effect == DaemonEffect.EXTRACT_DAEMON }
        if (extractors.isEmpty()) return emptyList<Opened>() to false
        val slots = ArrayList<LootSlot>()
        val claimed = HashMap<String, Int>()
        // Занято: открыто взломом другой сессии или уже открыто этой же (мастер сбросил остывание, `breach_cooldown_s` < `open_s`):
        // второй взлом не выбирает хранилище, которое игрок и так может взять, а ищет другое или даёт `exhausted`.
        val ownOpened = ops.openedItems(s, now).toSet()
        for (id in q.vaults) {
            val slot = vaultSlot(id) ?: continue
            claimed[slotRef(slots.size)] = if (id in ownOpened || ops.openedByOther(s.id, id, now) != null) 1 else 0
            slots += slot
        }
        val container = Container(q.node, VJ.str(nd.data, "title") ?: q.node, tier, "", slots)
        val taken = LinkedHashSet<Int>()
        var exhausted = false
        for (d in extractors) {
            val type = if (d.effect == DaemonEffect.EXTRACT_SHARD) LootType.SHARD else LootType.DAEMON
            val index = runBlocking { SlotPicker.pickSlot(container, type, d.tier, taken) { claimed[it] ?: 0 } }
            if (index == null) exhausted = true else taken += index
        }
        val until = now + q.openS * MS
        return taken.map { Opened(slots[it].payload, until) } to exhausted
    }

    /** Хранилище как слот для [SlotPicker]: предмет узла вида SHARD/DAEMON с разобранным тиром; иначе null (не лежит в узле — пропускаем). */
    private fun vaultSlot(id: String): LootSlot? {
        val item = tx.get(ValueOps.ITEM, id) ?: return null
        val type = LootType.entries.firstOrNull { it.name == VJ.str(item.data, "kind") } ?: return null
        val itemTier = ItemFacts.tier(item)
        if (VJ.str(item.data, "owner") != "node:${q.node}" || itemTier == null) return null
        return LootSlot(type, itemTier, copies = 1, payload = id)
    }

    private fun slotRef(index: Int) = "${q.node}#$index"

    // ---------- сигнал СБ ----------

    private fun decideAlert(s: Doc, nd: Doc, runner: Doc?, result: BreachOutcome, effects: Set<DaemonEffect>): AlertPlan? {
        val owner = ownerFaction(nd)
        val intruder = runner?.let { VJ.str(it.data, "faction") }.orEmpty()
        val plan = SecAlertRules.decide(owner, intruder, tier, result, effects, now)
        ops.log("breach.alert_decide session=${s.id} node=${q.node} n=${q.n} outcome=${result.name} owner=$owner suppressed=${plan == null}")
        return plan
    }

    /** Фракция-владелец узла: `node.owner_faction`, иначе `settings/sec.default_faction` (как правило P3). */
    private fun ownerFaction(nd: Doc): String =
        VJ.str(nd.data, "owner_faction")?.takeIf { it.isNotBlank() }
            ?: tx.get(ValueOps.SETTINGS, "sec")?.data?.let { VJ.str(it, "default_faction") }.orEmpty()

    private class AlertInfo(val id: String, val sendAt: Long, val callsign: Boolean, val precise: Boolean)

    /** Документ `sec_alert` (протокол, раздел 5): id от `<namespace>|<rid>`, отправляет его правило [BreachAlertRule] в `send_at`. */
    private fun writeAlert(s: Doc, nd: Doc, plan: AlertPlan): AlertInfo {
        val id = "sa_" + VJ.sha256Hex("${caller.namespace}|$rid").take(ALERT_ID_HEX)
        val owner = ownerFaction(nd)
        tx.put(
            BreachAlertRule.TYPE, id, 0,
            VJ.obj(
                "state" to VJ.p("pending"), "send_at" to VJ.p(plan.sendAt), "ttl_at" to VJ.p(now + ALERT_TTL_MS), "faction" to VJ.p(owner),
                "node" to VJ.p(q.node), "title" to VJ.p(VJ.str(nd.data, "title")?.takeIf { it.isNotBlank() } ?: q.node),
                "tier" to VJ.p(tier.level.toLong()),
                "callsign" to VJ.p(if (plan.revealCallsign) VJ.str(s.data, "callsign") else null),
                "precise_at" to (if (plan.revealPreciseTime) VJ.p(now) else JsonNull),
                "session" to VJ.p(s.id), "rid" to VJ.p(rid),
            ),
        )
        return AlertInfo(id, plan.sendAt, plan.revealCallsign, plan.revealPreciseTime)
    }

    // ---------- записи ----------

    private fun writeNode(nd: Doc, eddies: Long) {
        if (eddies > 0) tx.put(ValueOps.NODE, nd.id, nd.ver, VJ.with(nd.data, "eddies" to VJ.p(VJ.lng(nd.data, "eddies") - eddies)))
    }

    /** Сессия: добыча эдди, итог попытки, открытые хранилища (истёкшие удаляются). Возвращает добычу эдди сессии. */
    @Suppress("LongParameterList")
    private fun writeSession(
        s: Doc,
        result: BreachOutcome,
        effects: Set<DaemonEffect>,
        eddies: Long,
        opened: List<Opened>,
        exhausted: Boolean,
        alert: AlertInfo?,
    ): Long {
        val fresh = opened.map { it.item }.toSet()
        val live = (s.data["opened"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
            .filter { VJ.lng(it, "until") > now && VJ.str(it, "item") !in fresh }
        val all = live + opened.map { VJ.obj("item" to VJ.p(it.item), "node" to VJ.p(q.node), "until" to VJ.p(it.until)) }
        val loot = VJ.lng(s.data, "loot_eddies") + eddies
        val breach = VJ.obj(
            "n" to VJ.p(q.n), "node" to VJ.p(q.node), "tier" to VJ.p(tier.name), "outcome" to VJ.p(result.name),
            "effects" to VJ.arr(effects.map { it.name }), "eddies" to VJ.p(eddies), "opened_n" to VJ.p(opened.size.toLong()),
            "exhausted" to VJ.p(exhausted), "alert" to VJ.p(alert?.id), "at" to VJ.p(now),
        )
        tx.put(ValueOps.SESSION, s.id, s.ver, VJ.with(s.data, "loot_eddies" to VJ.p(loot), "breach" to breach, "opened" to JsonArray(all)))
        return loot
    }

    private fun breachCooldown(runner: Doc): Map<String, Long> =
        (runner.data["breach_cooldown"] as? JsonObject)?.mapValues { (it.value as? JsonPrimitive)?.longOrNull ?: 0L }.orEmpty()

    /** Остывание узла для нетраннера; ключи с истёкшим сроком удаляются той же записью. */
    private fun writeRunner(runner: Doc?, key: String, s: Doc, cooldown: Map<String, Long>, until: Long) {
        val next = (cooldown.filterValues { it > now } + (q.node to until)).toSortedMap()
        val cooled = JsonObject(next.mapValues { VJ.p(it.value) })
        val base = runner?.data ?: ops.newRunner(key, VJ.str(s.data, "callsign").orEmpty())
        val data = VJ.with(base, "breach_cooldown" to cooled)
        if (runner == null) tx.put(ValueOps.RUNNER, ValueOps.runnerDocId(key), 0, data) else tx.put(ValueOps.RUNNER, runner.id, runner.ver, data)
    }

    @Suppress("LongParameterList")
    private fun response(
        result: BreachOutcome,
        effects: Set<DaemonEffect>,
        eddies: Long,
        loot: Long,
        opened: List<Opened>,
        exhausted: Boolean,
        cooldownUntil: Long,
        alert: AlertInfo?,
    ): JsonObject = VJ.obj(
        "outcome" to VJ.p(result.name), "effects" to VJ.arr(effects.map { it.name }), "eddies" to VJ.p(eddies), "loot_eddies" to VJ.p(loot),
        "opened" to JsonArray(opened.map { VJ.obj("item" to VJ.p(it.item), "until" to VJ.p(it.until)) }),
        "exhausted" to VJ.p(exhausted), "cooldown_until" to VJ.p(cooldownUntil),
        "alert" to (
            alert?.let { VJ.obj("id" to VJ.p(it.id), "send_at" to VJ.p(it.sendAt), "callsign" to VJ.p(it.callsign), "precise" to VJ.p(it.precise)) }
                ?: JsonNull
            ),
    )

    private companion object {
        const val MS = 1000L
        const val SEC_PER_MIN = 60L
        const val SEED_HEX = 16
        const val HEX = 16
        const val ALERT_ID_HEX = 16
        const val ALERT_TTL_MS = 30 * 60_000L
    }
}
