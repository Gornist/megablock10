package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.LogFormat
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.signaturePayload
import com.megablok10.netrun.bridge.Change
import com.megablok10.netrun.bridge.CommitHook
import com.megablok10.netrun.bridge.Doc
import com.megablok10.netrun.bridge.DocKey
import com.megablok10.netrun.bridge.phone.WorldKey
import java.sql.Connection

/**
 * Подписывает события мира ключом мира и кладёт их в [WorldRecordQueue] в транзакции хранилища ([CommitHook]): документы и запись о
 * них фиксируются одним `COMMIT`. Сам по себе ничего не отправляет — отправляет `SyncEngine` ([WorldSync]).
 *
 * Заодно выводит быстрые события для точек площадки ([WorldFastEvents], раздел 3 контракта) из тех же изменений документов: они не пишутся
 * ни в [queue], ни в `SyncEngine`, а после `COMMIT` отдаются [fastSink] (неблокирующее: сеть — не под замком хранилища). Без [fastSink]
 * (коллектор не задан) события не выводятся вовсе.
 *
 * Сбой разбора событий (ошибка в [WorldRecords.derive]) игру не останавливает: он пишется в журнал уровнем ERROR (`world.derive_failed`
 * с id документов транзакции), а транзакция документов идёт дальше, потому что записи о мире — отчёт, а не ценность. Сбой SQLite наоборот откатывает всё: запись и данные не расходятся.
 */
internal class WorldRecorder(
    private val queue: WorldRecordQueue,
    private val key: WorldKey,
    private val epoch: String,
    private val log: KitLog = NoopLog,
    private val fastSink: ((List<FastEvent>) -> Unit)? = null,
) : CommitHook {
    /** Записи последней транзакции: журнал и пробуждение отправки — только после её `COMMIT` ([committed]), откат их стирает. */
    private var staged: List<ChangeRecord> = emptyList()

    /** Быстрые события последней транзакции: уходят в [fastSink] только после её `COMMIT`, как и [staged]. */
    private var stagedFast: List<FastEvent> = emptyList()

    override fun beforeCommit(conn: Connection, changes: List<Change>, previous: (DocKey) -> Doc?) {
        staged = emptyList()
        stagedFast = deriveFast(changes, previous)
        val events = try {
            WorldRecords.derive(changes, previous)
        } catch (e: RuntimeException) {
            // Известное ограничение (docs/netrun-world-records.md, раздел 7): игра важнее отчёта, транзакция документов идёт дальше, а записи
            // мира за неё не появятся и не будут восстановлены сами. Поэтому не предупреждение, а ERROR с id документов для ручной сверки.
            val docs = changes.take(LOGGED_DOCS).joinToString(",") { "${it.doc.type}/${it.doc.id}" } + if (changes.size > LOGGED_DOCS) ",…" else ""
            log.e(TAG, LogFormat.event("world.derive_failed", arrayOf("error" to e.javaClass.simpleName, "msg" to e.message, "tx" to changes.firstOrNull()?.seq, "docs" to docs)), e)
            return
        }
        staged = events.mapNotNull { enqueue(conn, it) }
    }

    /** Сбой вывода быстрых событий — предупреждение, не ошибка: событие живёт секунды, а записи мира и транзакция от него не зависят. */
    private fun deriveFast(changes: List<Change>, previous: (DocKey) -> Doc?): List<FastEvent> {
        if (fastSink == null) return emptyList()
        return try {
            WorldFastEvents.derive(changes, previous, epoch)
        } catch (e: RuntimeException) {
            log.warnEvent(TAG, "world.fast_derive_failed", "error" to e.javaClass.simpleName, "tx" to changes.firstOrNull()?.seq)
            emptyList()
        }
    }

    /** null — запись с таким id уже есть (повтор того же события): `seq` на неё не тратится. */
    private fun enqueue(conn: Connection, e: WorldEvent): ChangeRecord? {
        val id = e.id(epoch)
        if (queue.contains(conn, id)) {
            log.warnEvent(TAG, "world.record_duplicate", "id" to id)
            return null
        }
        val unsigned = ChangeRecord(
            id = id, subjectKeyB64 = key.publicB64, seq = queue.nextSeq(conn), happenedAt = e.happenedAt, field = e.field,
            oldValue = null, newValue = e.value.toString(), reason = e.reason, sourceRef = e.sourceRef, actor = key.publicB64, signature = "",
        )
        return unsigned.copy(signature = key.sign(unsigned.signaturePayload())).also { queue.insert(conn, it) }
    }

    /** После `COMMIT` транзакции: записи легли в очередь — в журнал и (если что-то появилось) разбудить отправку. */
    fun committed(onQueued: () -> Unit) {
        val done = staged
        staged = emptyList()
        for (r in done) log.event(TAG, "record.enqueued", "field" to r.field, "reason" to r.reason, "seq" to r.seq, "ref" to r.sourceRef)
        if (done.isNotEmpty()) onQueued()
        val fast = stagedFast
        stagedFast = emptyList()
        if (fast.isNotEmpty()) fastSink?.invoke(fast)
    }

    companion object {
        const val TAG = "WorldRecords"
        private const val LOGGED_DOCS = 20
    }
}
