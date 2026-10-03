package com.megablok10.netrun.bridge.collector

import com.megablok10.netrun.bridge.Change
import com.megablok10.netrun.bridge.Doc
import com.megablok10.netrun.bridge.DocKey
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueOps
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Запись мира до подписи (docs/netrun-world-records.md, раздел 2): [field] и [reason] из C2, [sourceRef] — id документа Моста,
 * из-за которого она пишется, [ver] — его версия после изменения, [happenedAt] — его `updated`, [value] — тело `newValue`.
 * Эпоха базы (`DocStore.epoch`) в событие не входит: она нужна только для [id].
 */
internal class WorldEvent(
    val field: String,
    val reason: String,
    val sourceRef: String,
    val ver: Long,
    val happenedAt: Long,
    val value: JsonObject,
) {
    /**
     * `id` записи: `w:<field>:<эпоха>:<sourceRef>:<ver>`. В пределах одной базы он детерминирован, поэтому повтор после сбоя Моста
     * не плодит дублей; эпоха базы [epoch] отличает «жизни» базы, чтобы после сброса (тот же ключ мира, `ver` снова с 1) коллектор
     * не отверг новые записи как «id already used», а kit не удалил их как отвергнутые.
     */
    fun id(epoch: String): String = "w:$field:$epoch:$sourceRef:$ver"
}

/** Названия полей и причин записей мира: ровно те, что принимает коллектор (`lib/changeRecord.ts`). */
internal object WorldRecords {
    const val RUN = "net.run"
    const val ITEM = "net.item"
    const val ALERT = "net.alert"
    const val ENTER = "NET_ENTER"
    const val EXIT = "NET_EXIT"
    const val FLATLINE = "NET_FLATLINE"
    const val ITEM_OWNER = "NET_ITEM_OWNER"
    const val ALERT_REASON = "NET_ALERT"

    /** Предел `newValue` на стороне коллектора (`MAX_JSON_CHARS`). */
    const val MAX_VALUE_CHARS = 4096

    /**
     * События мира, которые породила одна транзакция [changes] хранилища ([previous] — документ до неё). Только чтение: выводится из
     * разницы документов, поэтому операции с ценностями не знают о записях, а запись не может разойтись с тем, что случилось.
     */
    fun derive(changes: List<Change>, previous: (DocKey) -> Doc?): List<WorldEvent> = Derivation(changes, previous).run()
}

private const val CALLSIGN_MAX = 64
private const val ALERT_MSG_MAX = 1000
private const val ALERT_ITEMS_MAX = 20
private const val MS_IN_S = 1000L

/** Состояние сессии, значения `owner` предметов и виды тревог — слова протокола Моста (разделы 4 и 5). */
private object Words {
    const val PENDING = "pending"
    const val CLOSED = "closed"
    const val BLACK_ICE = "black_ice"
    const val SOFT_ICE = "soft_ice"
    const val FLATLINE_KIND = "flatline"
    const val OP_ISSUE = "issue_to_phone"
}

/** Один разбор транзакции: что было, что стало, какая операция её породила. */
private class Derivation(changes: List<Change>, private val previous: (DocKey) -> Doc?) {
    private val now: Map<DocKey, Doc> = changes.filterNot { it.deleted }.associate { DocKey(it.doc.type, it.doc.id) to it.doc }

    /** Операция, записавшая `op_rid` в этой транзакции (`rid` и имя операции); null — транзакция не от операции с ценностями. */
    private val op: Pair<String, String?>? by lazy { findOp() }

    fun run(): List<WorldEvent> = sessionEvents() + itemEvents() + alertEvents()

    private fun docs(type: String): List<Doc> = now.values.filter { it.type == type }.sortedBy { it.id }

    private fun before(d: Doc): Doc? = previous(DocKey(d.type, d.id))

    private fun lookup(type: String, id: String): Doc? = now[DocKey(type, id)] ?: previous(DocKey(type, id))

    // ---------- сессии: вход и выход ----------

    private fun sessionEvents(): List<WorldEvent> = docs(ValueOps.SESSION).mapNotNull { s ->
        val prev = before(s)
        when {
            prev == null && VJ.str(s.data, "state") == Words.PENDING -> enter(s)
            prev != null && VJ.str(prev.data, "state") != Words.CLOSED && VJ.str(s.data, "state") == Words.CLOSED -> leave(s)
            else -> null
        }
    }

    private fun enter(s: Doc): WorldEvent {
        val value = runBase(s, VJ.str(s.data, "node"))
        lookup(ValueOps.DECK, s.id)?.let { deck ->
            value["deck"] = VJ.p(VJ.list(deck.data, "items").size.toLong())
            value["protected"] = VJ.p(!VJ.str(deck.data, "protected").isNullOrEmpty())
        }
        return event(WorldRecords.RUN, WorldRecords.ENTER, s, value)
    }

    /** Закрытие сессии: флэтлайн (`black_ice`) и все остальные исходы — взаимоисключающие записи. */
    private fun leave(s: Doc): WorldEvent {
        val outcome = VJ.str(s.data, "outcome") ?: "unknown"
        val node = currentNode(s)
        val value = runBase(s, node)
        value["outcome"] = VJ.p(outcome)
        if (outcome == Words.BLACK_ICE) return flatline(s, value)
        val moved = movedFromDeck(s.id)
        value["duration_s"] = VJ.p(durationS(s))
        value["returned"] = VJ.p(moved.count { it.startsWith("outbox:") }.toLong())
        value["burned"] = VJ.p(moved.count { it.startsWith("burned:") }.toLong())
        value["left_in_node"] = VJ.p(moved.count { it.startsWith("node:") }.toLong())
        value["eddies_paid"] = VJ.p(VJ.lng(s.data, "eddies_paid"))
        val lockdown = if (outcome == Words.SOFT_ICE && node != null) now[DocKey(ValueOps.NODE, node)]?.let { VJ.lng(it.data, "lockdown_until") } else null
        value["lockdown_until"] = VJ.p(lockdown ?: 0L)
        return event(WorldRecords.RUN, WorldRecords.EXIT, s, value)
    }

    private fun flatline(s: Doc, value: MutableMap<String, JsonElement>): WorldEvent {
        val disconnect = VJ.bool(s.data, "disconnect")
        value["disconnect"] = VJ.p(disconnect)
        value["duration_s"] = VJ.p(durationS(s))
        value["left_in_node"] = VJ.p(movedFromDeck(s.id).count { it.startsWith("node:") }.toLong())
        value["cause"] = VJ.p(if (disconnect) "обрыв до флэтлайна" else "флэтлайн")
        docs(ValueOps.ALERT).firstOrNull { before(it) == null && VJ.str(it.data, "kind") == Words.FLATLINE_KIND }?.let { value["alert"] = VJ.p(it.id) }
        return event(WorldRecords.RUN, WorldRecords.FLATLINE, s, value)
    }

    /** Общие поля `net.run`: сессия, нетраннер, позывной, терминал, узел; пустые не пишутся. */
    private fun runBase(s: Doc, node: String?): MutableMap<String, JsonElement> {
        val value = LinkedHashMap<String, JsonElement>()
        value["session"] = VJ.p(s.id)
        VJ.str(s.data, "runner")?.let { value["runner"] = VJ.p(it) }
        VJ.str(s.data, "callsign")?.let { value["callsign"] = VJ.p(cap(it, CALLSIGN_MAX)) }
        VJ.str(s.data, "terminal")?.let { value["terminal"] = VJ.p(it) }
        node?.let { value["node"] = VJ.p(it) }
        return value
    }

    /** Узел, где сессия сейчас: `world.node` (пишет сервер мира), иначе узел, куда её приняли. */
    private fun currentNode(s: Doc): String? = (s.data["world"] as? JsonObject)?.let { VJ.str(it, "node") } ?: VJ.str(s.data, "node")

    /** Длительность забега: от курка (`confirmed_at`, нет — от создания сессии) до закрытия. */
    private fun durationS(s: Doc): Long {
        val start = VJ.lng(s.data, "confirmed_at").takeIf { it > 0 } ?: s.created
        val end = VJ.lng(s.data, "finished_at").takeIf { it > 0 } ?: s.updated
        return (end - start).coerceAtLeast(0) / MS_IN_S
    }

    /** Новые владельцы предметов, которые в этой транзакции вышли из деки [sid] (`outbox:` — вернулись, `burned:` — сгорели, `node:` — в узле). */
    private fun movedFromDeck(sid: String): List<String> =
        docs(ValueOps.ITEM).filter { owner(before(it)) == "deck:$sid" }.mapNotNull { owner(it) }

    // ---------- предметы: значимые смены владельца ----------

    private fun itemEvents(): List<WorldEvent> = docs(ValueOps.ITEM).mapNotNull { d ->
        val from = owner(before(d)) ?: return@mapNotNull null
        val to = owner(d) ?: return@mapNotNull null
        if (from != to && significant(from, to)) item(d, from, to) else null
    }

    private fun item(d: Doc, from: String, to: String): WorldEvent {
        val value = LinkedHashMap<String, JsonElement>()
        value["item"] = VJ.p(d.id)
        VJ.str(d.data, "kind")?.let { value["kind"] = VJ.p(it) }
        value["from"] = VJ.p(from)
        value["to"] = VJ.p(to)
        val sid = sessionOf(from) ?: sessionOf(to)
        sid?.let { value["session"] = VJ.p(it) }
        val runner = sid?.let { lookup(ValueOps.SESSION, it) }?.let { VJ.str(it.data, "runner") } ?: runnerOf(to) ?: runnerOf(from)
        runner?.let { value["runner"] = VJ.p(it) }
        val (opName, rid) = itemOp(d, to)
        opName?.let { value["op"] = VJ.p(it) }
        rid?.let { value["rid"] = VJ.p(it) }
        return event(WorldRecords.ITEM, WorldRecords.ITEM_OWNER, d, value)
    }

    /** Операция и `rid`: из `op_rid` этой транзакции; чек телефона (`phone:`) идёт без операции — это `issue_to_phone`, а `rid` — id карточки. */
    private fun itemOp(d: Doc, to: String): Pair<String?, String?> {
        op?.let { (rid, name) -> return name to rid }
        return if (to.startsWith("phone:")) Words.OP_ISSUE to VJ.str(d.data, "out_transfer") else null to null
    }

    private fun findOp(): Pair<String, String?>? = docs(ValueOps.RID_TYPE).filter { before(it) == null }.mapNotNull { rec ->
        val name = runCatching { (Json.parseToJsonElement(VJ.str(rec.data, "params").orEmpty()) as? JsonObject)?.let { VJ.str(it, "op") } }.getOrNull()
        VJ.str(rec.data, "rid")?.let { it to name }
    }.firstOrNull { it.second != "refund" }

    // ---------- тревоги ----------

    /** Новая тревога Моста. Флэтлайн отдельной записью не дублируется: он уже `NET_FLATLINE` с id тревоги. */
    private fun alertEvents(): List<WorldEvent> = docs(ValueOps.ALERT)
        .filter { before(it) == null && VJ.str(it.data, "kind") != Words.FLATLINE_KIND }
        .map { a ->
            val value = LinkedHashMap<String, JsonElement>()
            value["alert"] = VJ.p(a.id)
            value["kind"] = VJ.p(VJ.str(a.data, "kind").orEmpty())
            value["msg"] = VJ.p(cap(VJ.str(a.data, "msg").orEmpty(), ALERT_MSG_MAX))
            value["items"] = JsonArray(VJ.list(a.data, "items").take(ALERT_ITEMS_MAX).map { JsonPrimitive(it) })
            event(WorldRecords.ALERT, WorldRecords.ALERT_REASON, a, value)
        }

    // ---------- сборка ----------

    private fun event(field: String, reason: String, source: Doc, value: MutableMap<String, JsonElement>): WorldEvent =
        WorldEvent(field, reason, source.id, source.ver, source.updated, fitted(value))
}

private fun owner(d: Doc?): String? = d?.let { VJ.str(it.data, "owner") }

/** Сессия из `deck:<s>` или `burned:<s>`; `burned:master` — убрано мастером, сессии нет. */
private fun sessionOf(owner: String): String? =
    listOf("deck:", "burned:").firstNotNullOfOrNull { p -> owner.removePrefix(p).takeIf { owner.startsWith(p) && it != "master" } }

private fun runnerOf(owner: String): String? =
    listOf("phone:", "outbox:", "inbox:").firstNotNullOfOrNull { p -> owner.removePrefix(p).takeIf { owner.startsWith(p) } }

/**
 * Значимые для игры переходы (C2, 2.5): предмет лёг в узел (оставлен, мёртвая дека), взят из узла в деку, сгорел, ушёл на телефон
 * (чек получен). Переходы `inbox → deck`, `deck → outbox` внутри забега видны как вход и выход и в записи предмета не пишутся.
 */
private fun significant(from: String, to: String): Boolean = when {
    to.startsWith("node:") -> true
    from.startsWith("node:") && to.startsWith("deck:") -> true
    to.startsWith("burned:") -> true
    to.startsWith("phone:") -> true
    else -> false
}

/** `newValue` не длиннее предела коллектора: единственное длинное поле — `msg` тревоги, его и укорачиваем. */
private fun fitted(value: MutableMap<String, JsonElement>): JsonObject {
    var obj = JsonObject(value)
    var msg = (value["msg"] as? JsonPrimitive)?.content.orEmpty()
    while (obj.toString().length > WorldRecords.MAX_VALUE_CHARS && msg.isNotEmpty()) {
        msg = cap(msg, msg.length / 2)
        value["msg"] = VJ.p(msg)
        obj = JsonObject(value)
    }
    return obj
}

/** Строка не длиннее [max] символов, без разрезанной суррогатной пары (иначе подпись и тело разошлись бы в байтах). */
private fun cap(s: String, max: Int): String {
    if (s.length <= max) return s
    val cut = if (max > 0 && s[max - 1].isHighSurrogate()) max - 1 else max
    return s.substring(0, cut)
}
