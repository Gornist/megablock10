package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.sync.ChangeQueue
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.netrun.bridge.DocStore
import java.sql.Connection
import java.sql.ResultSet

/**
 * Очередь записей мира для коллектора в той же SQLite, что и документы Моста: таблица `world_records`, номер `seq` — строка
 * `world_record_seq` в `meta`. Это и нужно контракту (C2, 2.1): запись ставится в очередь в транзакции изменения документов
 * ([WorldRecorder]), поэтому «изменение есть, записи нет» и «записи нет, изменения нет» невозможны.
 *
 * Строка без `accepted_at` ждёт отправки; подтверждённая коллектором остаётся в таблице [retentionMs] (журнал подтверждённых, как
 * `accepted_change_records` на телефоне): если коллектор восстановили из резервной копии, kit вернёт записи сверх его `knownSeq`
 * в очередь ([requeueAcceptedAbove]). Доступ к соединению — под замком [DocStore], общим с транзакциями документов.
 */
class WorldRecordQueue(
    private val store: DocStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val retentionMs: Long = DEFAULT_RETENTION_MS,
) : ChangeQueue {
    init {
        store.withConnection { c ->
            c.createStatement().use { st ->
                st.execute(
                    "CREATE TABLE IF NOT EXISTS world_records(id TEXT PRIMARY KEY, subject TEXT NOT NULL, seq INTEGER NOT NULL, " +
                        "happened_at INTEGER NOT NULL, field TEXT NOT NULL, old_value TEXT, new_value TEXT, reason TEXT NOT NULL, " +
                        "source_ref TEXT, actor TEXT NOT NULL, signature TEXT NOT NULL, accepted_at INTEGER)",
                )
                st.execute("CREATE INDEX IF NOT EXISTS world_records_queue ON world_records(accepted_at, seq)")
            }
        }
    }

    // ---------- вызовы из транзакции документов (соединение уже под транзакцией хранилища) ----------

    internal fun contains(c: Connection, id: String): Boolean =
        c.prepareStatement("SELECT 1 FROM world_records WHERE id=?").use { st ->
            st.setString(1, id)
            st.executeQuery().use { it.next() }
        }

    /** Следующий `seq`: растёт монотонно и не зависит от очереди (подтверждённые записи могут уйти из журнала, нумерация — нет). */
    internal fun nextSeq(c: Connection): Long {
        val next = lastSeq(c) + 1
        c.prepareStatement("INSERT OR REPLACE INTO meta(key,value) VALUES ('$SEQ_KEY',?)").use { st ->
            st.setLong(1, next)
            st.executeUpdate()
        }
        return next
    }

    internal fun lastSeq(c: Connection): Long = c.createStatement().use { st ->
        st.executeQuery("SELECT value FROM meta WHERE key='$SEQ_KEY'").use { rs ->
            if (rs.next()) rs.getLong(1) else maxSeq(c)
        }
    }

    private fun maxSeq(c: Connection): Long = c.createStatement().use { st ->
        st.executeQuery("SELECT COALESCE(MAX(seq),0) FROM world_records").use { rs -> rs.next(); rs.getLong(1) }
    }

    /** Повторная запись с тем же id игнорируется (контракт [ChangeQueue.insert]). */
    internal fun insert(c: Connection, r: ChangeRecord) {
        c.prepareStatement(
            "INSERT OR IGNORE INTO world_records(id,subject,seq,happened_at,field,old_value,new_value,reason,source_ref,actor,signature,accepted_at) " +
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,NULL)",
        ).use { st ->
            st.setString(1, r.id)
            st.setString(2, r.subjectKeyB64)
            st.setLong(3, r.seq)
            st.setLong(4, r.happenedAt)
            st.setString(5, r.field)
            st.setString(6, r.oldValue)
            st.setString(7, r.newValue)
            st.setString(8, r.reason)
            st.setString(9, r.sourceRef)
            st.setString(10, r.actor)
            st.setString(11, r.signature)
            st.executeUpdate()
        }
    }

    // ---------- kit ChangeQueue (зовёт SyncEngine) ----------

    override suspend fun nextSeq(): Long = store.withConnection { c -> atomically(c) { nextSeq(c) } }

    override suspend fun lastSeq(): Long = store.withConnection { c -> lastSeq(c) }

    override suspend fun insert(record: ChangeRecord) = store.withConnection { c -> atomically(c) { insert(c, record) } }

    override suspend fun nextBatch(limit: Int): List<ChangeRecord> = store.withConnection { c ->
        c.prepareStatement("SELECT * FROM world_records WHERE accepted_at IS NULL ORDER BY seq ASC LIMIT ?").use { st ->
            st.setInt(1, limit)
            st.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.toRecord() else null }.toList() }
        }
    }

    override suspend fun deleteByIds(ids: List<String>) = store.withConnection { c ->
        atomically(c) { ids.chunked(CHUNK).forEach { part -> c.exec("DELETE FROM world_records WHERE id IN (${marks(part)})", part) } }
    }

    /** Подтверждённые — в журнал; заодно из него уходит всё старше [retentionMs]. */
    override suspend fun markAccepted(ids: List<String>) = store.withConnection { c ->
        val at = clock()
        atomically(c) {
            ids.chunked(CHUNK).forEach { part ->
                c.exec("UPDATE world_records SET accepted_at=$at WHERE accepted_at IS NULL AND id IN (${marks(part)})", part)
            }
            c.exec("DELETE FROM world_records WHERE accepted_at IS NOT NULL AND accepted_at < ?", emptyList(), at - retentionMs)
        }
    }

    /** Коллектор потерял подтверждённые записи (восстановлен из копии): вернуть из журнала в очередь всё сверх его последнего [seq]. */
    override suspend fun requeueAcceptedAbove(subjectKeyB64: String, seq: Long): Int = store.withConnection { c ->
        atomically(c) {
            c.prepareStatement("UPDATE world_records SET accepted_at=NULL WHERE accepted_at IS NOT NULL AND subject=? AND seq>?").use { st ->
                st.setString(1, subjectKeyB64)
                st.setLong(2, seq)
                st.executeUpdate()
            }
        }
    }

    override suspend fun count(): Int = store.withConnection { c ->
        c.createStatement().use { st -> st.executeQuery("SELECT COUNT(*) FROM world_records WHERE accepted_at IS NULL").use { rs -> rs.next(); rs.getInt(1) } }
    }

    override suspend fun oldestHappenedAt(): Long? = store.withConnection { c ->
        c.createStatement().use { st ->
            st.executeQuery("SELECT MIN(happened_at) FROM world_records WHERE accepted_at IS NULL").use { rs -> if (rs.next()) rs.getLong(1).takeUnless { rs.wasNull() } else null }
        }
    }

    // ---------- помощники ----------

    /** Несколько операторов одной транзакцией; внутри транзакции хранилища (автофиксация выключена) просто присоединяемся к ней. */
    private fun <T> atomically(c: Connection, block: () -> T): T {
        if (!c.autoCommit) return block()
        c.autoCommit = false
        try {
            val r = block()
            c.commit()
            return r
        } catch (e: Exception) {
            runCatching { c.rollback() }
            throw e
        } finally {
            c.autoCommit = true
        }
    }

    private fun Connection.exec(sql: String, ids: List<String>, vararg extra: Long) {
        prepareStatement(sql).use { st ->
            var i = 1
            ids.forEach { st.setString(i++, it) }
            extra.forEach { st.setLong(i++, it) }
            st.executeUpdate()
        }
    }

    private fun marks(part: List<String>) = part.joinToString(",") { "?" }

    private fun ResultSet.toRecord() = ChangeRecord(
        getString("id"), getString("subject"), getLong("seq"), getLong("happened_at"), getString("field"), getString("old_value"),
        getString("new_value"), getString("reason"), getString("source_ref"), getString("actor"), getString("signature"),
    )

    companion object {
        private const val SEQ_KEY = "world_record_seq"
        private const val CHUNK = 400

        /** Сколько хранить подтверждённые записи: с запасом больше интервала резервных копий коллектора (как на телефоне). */
        const val DEFAULT_RETENTION_MS = 6 * 60 * 60 * 1000L
    }
}
