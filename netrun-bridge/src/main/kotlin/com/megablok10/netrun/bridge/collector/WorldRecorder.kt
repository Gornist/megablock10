package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.KitLog
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
 * Сбой разбора событий (ошибка в [WorldRecords.derive]) игру не останавливает: он пишется в журнал, а транзакция документов идёт
 * дальше, потому что записи о мире — отчёт, а не ценность. Сбой SQLite наоборот откатывает всё: запись и данные не расходятся.
 */
internal class WorldRecorder(
    private val queue: WorldRecordQueue,
    private val key: WorldKey,
    private val log: KitLog = NoopLog,
) : CommitHook {
    /** Записи последней транзакции: журнал и пробуждение отправки — только после её `COMMIT` ([committed]), откат их стирает. */
    private var staged: List<ChangeRecord> = emptyList()

    override fun beforeCommit(conn: Connection, changes: List<Change>, previous: (DocKey) -> Doc?) {
        staged = emptyList()
        val events = try {
            WorldRecords.derive(changes, previous)
        } catch (e: RuntimeException) {
            log.warnEvent(TAG, "world.derive_failed", "error" to e.javaClass.simpleName, "msg" to e.message)
            return
        }
        staged = events.mapNotNull { enqueue(conn, it) }
    }

    /** null — запись с таким id уже есть (повтор того же события): `seq` на неё не тратится. */
    private fun enqueue(conn: Connection, e: WorldEvent): ChangeRecord? {
        if (queue.contains(conn, e.id)) {
            log.warnEvent(TAG, "world.record_duplicate", "id" to e.id)
            return null
        }
        val unsigned = ChangeRecord(
            id = e.id, subjectKeyB64 = key.publicB64, seq = queue.nextSeq(conn), happenedAt = e.happenedAt, field = e.field,
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
    }

    companion object {
        const val TAG = "WorldRecords"
    }
}
