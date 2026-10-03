package com.megablok10.netrun.bridge.collector

import com.megablok10.netrun.bridge.Change
import com.megablok10.netrun.bridge.Doc
import com.megablok10.netrun.bridge.DocKey
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueOps
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Быстрое событие на точки площадки (docs/netrun-world-records.md, раздел 3) до отправки: свет, звук, экран точки. Данные оно не меняет
 * и теряться может без вреда, поэтому в очередь `SyncEngine` и в `world_records` не попадает (в отличие от записей мира, раздел 2).
 * Поля — ровно те, что разбирает коллектор (`admin-web/server/src/lib/worldEvents.ts`, `parseWorldEvent`).
 */
internal data class FastEvent(
    val id: String,
    val kind: String,
    /** Когда это случилось, мс (время изменения документа): по нему коллектор и Мост считают срок жизни [ttlMs]. */
    val ts: Long,
    val ttlMs: Long,
    val node: String?,
    val terminal: String?,
    val session: String?,
    /** Уровень trace словом (`SUSPICIOUS`, `TRACE`, `LOCKDOWN`…), только у `trace.level`. */
    val level: String?,
)

/** Виды быстрых событий: ровно семь, как в `WORLD_EVENT_KINDS` коллектора (его приём отбрасывает всё остальное как невалидное). */
internal object FastKinds {
    const val RUN_ENTER = "run.enter"
    const val RUN_EXIT = "run.exit"
    const val TRACE_LEVEL = "trace.level"
    const val ICE_HUNT = "ice.hunt"
    const val FLATLINE = "flatline"
    const val LOCKDOWN = "lockdown"
    const val ALERT_MASTER = "alert.master"

    val ALL = listOf(RUN_ENTER, RUN_EXIT, TRACE_LEVEL, ICE_HUNT, FLATLINE, LOCKDOWN, ALERT_MASTER)
}

/**
 * Вывод быстрых событий из той же транзакции хранилища, что и записи мира ([WorldRecords.derive]; зовёт [WorldRecorder.beforeCommit]).
 * Только чтение документов «до» и «после»: операции с ценностями о событиях не знают. Уйдут события только после `COMMIT` — откат
 * транзакции их стирает вместе с документами.
 */
internal object WorldFastEvents {
    /** Срок жизни события (контракт, раздел 3: ≈ 5 с). Дольше сирена на площадке прозвучала бы невпопад. */
    const val TTL_MS = 5_000L

    /** `id` не длиннее предела приёма (`MAX_ID` коллектора). */
    const val MAX_ID = 100

    /** События, которые породила одна транзакция [changes] ([previous] — документ до неё); [epoch] — эпоха базы (`DocStore.epoch`). */
    fun derive(changes: List<Change>, previous: (DocKey) -> Doc?, epoch: String): List<FastEvent> = FastDerivation(changes, previous, epoch).run()

    /** Имя уровня trace по числу `TraceMeter.Level` сервера мира (`netrun/server/trace/trace_meter.gd`); null — число не из перечня. */
    fun traceLevelName(level: Int): String? = TRACE_LEVELS.getOrNull(level)

    private val TRACE_LEVELS = listOf("NORMAL", "SUSPICIOUS", "TRACE", "LOCKDOWN", "FLATLINE")
}

/** Один разбор транзакции. Отличия от записей мира — в том, что событий больше (смена уровня trace, охота, локдаун) и у них есть срок жизни. */
private class FastDerivation(changes: List<Change>, private val previous: (DocKey) -> Doc?, private val epoch: String) {
    /** Номер транзакции хранилища: общий у всех изменений одной транзакции. */
    private val txSeq: Long = changes.firstOrNull()?.seq ?: 0L

    private val now: Map<DocKey, Doc> = changes.filterNot { it.deleted }.associate { DocKey(it.doc.type, it.doc.id) to it.doc }

    fun run(): List<FastEvent> = sessionEvents() + lockdownEvents() + alertEvents()

    private fun docs(type: String): List<Doc> = now.values.filter { it.type == type }.sortedBy { it.id }

    private fun before(d: Doc): Doc? = previous(DocKey(d.type, d.id))

    // ---------- сессии: вход, выход, флэтлайн, trace, охота ----------

    private fun sessionEvents(): List<FastEvent> = docs(ValueOps.SESSION).flatMap { s -> sessionEvents(s, before(s)) }

    private fun sessionEvents(s: Doc, prev: Doc?): List<FastEvent> {
        val state = VJ.str(s.data, "state")
        val was = prev?.let { VJ.str(it.data, "state") }
        return when {
            // закрытие: сервер мира уже мог писать узел и trace, но после `closed` они площадке не нужны
            state == Words.CLOSED -> if (prev != null && was != Words.CLOSED) closing(s) else emptyList()
            state == Words.ACTIVE && was != Words.CLOSED -> buildList {
                if (was != Words.ACTIVE) add(ofSession(FastKinds.RUN_ENTER, s))
                traceLevel(s, prev)?.let { add(it) }
                hunt(s, prev)?.let { add(it) }
            }
            else -> emptyList()
        }
    }

    /** Исход `black_ice` — флэтлайн (отдельный звук) и затем общий выход; остальные исходы — только выход. */
    private fun closing(s: Doc): List<FastEvent> {
        val exit = ofSession(FastKinds.RUN_EXIT, s)
        return if (VJ.str(s.data, "outcome") == Words.BLACK_ICE) listOf(ofSession(FastKinds.FLATLINE, s), exit) else listOf(exit)
    }

    /** Смена `session.world.trace_level` (число `TraceMeter.Level`) у активной сессии; прежнее значение документа — NORMAL, если его не было. */
    private fun traceLevel(s: Doc, prev: Doc?): FastEvent? {
        val level = traceOf(s) ?: return null
        val name = WorldFastEvents.traceLevelName(level) ?: return null
        if (level == (prev?.let { traceOf(it) } ?: 0)) return null
        return ofSession(FastKinds.TRACE_LEVEL, s, name)
    }

    /** Охота Black ICE началась: сервер мира ставит `session.world.hunt = true` (docs/netrun-bridge-protocol.md); конец охоты событием не является. */
    private fun hunt(s: Doc, prev: Doc?): FastEvent? {
        val on = (s.data["world"] as? JsonObject)?.let { VJ.bool(it, "hunt") } ?: false
        val was = (prev?.data?.get("world") as? JsonObject)?.let { VJ.bool(it, "hunt") } ?: false
        return if (on && !was) ofSession(FastKinds.ICE_HUNT, s) else null
    }

    private fun traceOf(d: Doc): Int? {
        val raw = ((d.data["world"] as? JsonObject)?.get("trace_level") as? JsonPrimitive)?.content ?: return null
        return raw.toIntOrNull() ?: raw.toDoubleOrNull()?.toInt()
    }

    private fun ofSession(kind: String, s: Doc, level: String? = null) =
        event(kind, s.id, s.updated, sessionNode(s), VJ.str(s.data, "terminal"), s.id, level)

    // ---------- узел ушёл в локдаун ----------

    /**
     * `node.lockdown_until` стал в будущем, а раньше локдауна не было: выброс Soft ICE (`run.finish`) или цель мастера. Продление идущего
     * локдауна и его снятие (`0`) событием не являются. Сессия — та, что в этой же транзакции закрылась исходом `soft_ice` на этом узле.
     */
    private fun lockdownEvents(): List<FastEvent> = docs(ValueOps.NODE).mapNotNull { n ->
        val until = VJ.lng(n.data, "lockdown_until")
        val was = before(n)?.let { VJ.lng(it.data, "lockdown_until") } ?: 0L
        if (until <= n.updated || was > n.updated) return@mapNotNull null
        event(FastKinds.LOCKDOWN, n.id, n.updated, n.id, null, softIceSessionAt(n.id), null)
    }

    private fun softIceSessionAt(node: String): String? = docs(ValueOps.SESSION)
        .firstOrNull { s -> VJ.str(s.data, "outcome") == Words.SOFT_ICE && VJ.str(s.data, "state") == Words.CLOSED && sessionNode(s) == node }?.id

    // ---------- тревога мастеру ----------

    /**
     * Новая тревога аудитора (звонок мастеру, на площадку не идёт). Те же документы `alert`, что и у записи `NET_ALERT`: флэтлайн
     * уже `flatline`, а `master_request` и `net_query` — вызовы панели мастера, не тревога.
     */
    private fun alertEvents(): List<FastEvent> = docs(ValueOps.ALERT)
        .filter { a -> before(a) == null && VJ.str(a.data, "kind").let { it != Words.FLATLINE_KIND && it !in Words.MASTER_CALLS } }
        .map { a -> event(FastKinds.ALERT_MASTER, a.id, a.updated, VJ.str(a.data, "node"), VJ.str(a.data, "terminal"), VJ.str(a.data, "session"), null) }

    // ---------- сборка ----------

    /** `id` = `e:<эпоха>:<txSeq>:<вид>:<документ>`: одно событие — одна транзакция — один `id`; эпоха отличает «жизни» базы после её сброса. */
    private fun event(kind: String, ref: String, ts: Long, node: String?, terminal: String?, session: String?, level: String?) = FastEvent(
        id = "e:$epoch:$txSeq:$kind:$ref".take(WorldFastEvents.MAX_ID), kind = kind, ts = ts, ttlMs = WorldFastEvents.TTL_MS,
        node = node?.take(MAX_REF), terminal = terminal?.take(MAX_REF), session = session?.take(MAX_REF), level = level,
    )

    private companion object {
        /** Предел длины `node`/`terminal`/`session` на стороне приёма (`MAX_REF`). */
        const val MAX_REF = 100
    }
}
