package com.megablok10.app.identity

import com.megablok10.app.data.SEQUENCES_CREATE_SQL
import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Сброс сессии стирает игровые данные устройства, но не очередь неотправленных записей (на настоящем SQLite со схемой из экспорта). */
class SessionResetTest {
    private val schemaDir = File("schemas/com.megablok10.app.data.Mb10Database")
    private lateinit var conn: Connection

    @Before fun open() { conn = DriverManager.getConnection("jdbc:sqlite::memory:") }
    @After fun close() { conn.close() }

    private fun sql(q: String) { conn.createStatement().use { it.execute(q) } }
    private fun count(table: String): Int = conn.createStatement().use { st -> st.executeQuery("SELECT COUNT(*) FROM `$table`").use { it.next(); it.getInt(1) } }
    private fun tables(): List<String> = conn.createStatement().use { st ->
        st.executeQuery("SELECT name FROM sqlite_master WHERE type = 'table'").use { rs -> buildList { while (rs.next()) add(rs.getString(1)) } }
    }

    private fun createSchema() {
        val json = File(schemaDir, "13.json").readText()
        Regex("\"tableName\":\\s*\"(\\w+)\",\\s*\"createSql\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").findAll(json).forEach { m ->
            sql(m.groupValues[2].replace("\${TABLE_NAME}", m.groupValues[1]))
        }
    }

    @Test fun keepsOnlyThePendingQueueAndItsSeqCounter() {
        assertEquals(setOf("pending_change_records", "sequences"), SessionReset.KEEP_TABLES)
    }

    @Test fun wipesGameDataButKeepsUnsentRecords() {
        createSchema()
        sql("INSERT INTO transactions (id, counterpartyPubKeyB64, amount, memo, timestamp, status) VALUES ('tx-1', 'pk', 300, 'старый персонаж', 1, 'CONFIRMED')")
        sql("INSERT INTO consumed_tokens (token, consumedAt) VALUES ('ram-1', 2)")
        sql("INSERT INTO container_breaches (containerId, lastRewardedAt) VALUES ('c-1', 3)")
        sql("INSERT INTO outbox (toPubKeyB64, wireLine, createdAt, attempts, nextAttemptAt) VALUES ('pk', 'line', 1, 0, 0)")
        sql("INSERT INTO chat_messages (type, fromPubKeyB64, fromCallsign, faction, toPubKeyB64, body, timestamp) VALUES ('DM', 'a', 'A', 'F', 'b', 'привет', 4)")
        sql("INSERT INTO characters (publicKeyB64, callsign, faction, isNpc) VALUES ('pk-contact', 'Bob', 'Rats', 0)")
        sql("INSERT INTO pending_change_records (id, subjectKeyB64, seq, happenedAt, field, oldValue, newValue, reason, sourceRef, actor, signature) VALUES ('r-1', 'old-key', 1, 5, 'callsign', 'Alice', '', 'CHARACTER_RESET', NULL, 'old-key', 'sig')")
        sql(SEQUENCES_CREATE_SQL)
        sql("INSERT INTO sequences (name, value) VALUES ('change_seq', 1)")

        SessionReset.wipeStatements(tables()).forEach(::sql)

        listOf("transactions", "consumed_tokens", "container_breaches", "outbox", "chat_messages", "characters").forEach { assertEquals("$it должна быть пуста", 0, count(it)) }
        assertEquals("неотправленная запись о сбросе должна уцелеть", 1, count("pending_change_records"))
        assertEquals("счётчик номеров записей не сбрасывается — новые записи не повторят номера из очереди", 1, count("sequences"))
    }

    @Test fun everyTableExceptTheQueueIsWiped_evenOnesAddedLater() {
        createSchema()
        sql("CREATE TABLE future_feature (x TEXT)")
        sql("INSERT INTO future_feature VALUES ('данные новой фичи')")
        SessionReset.wipeStatements(tables()).forEach(::sql)
        assertEquals("новая таблица стирается по умолчанию", 0, count("future_feature"))
        assertTrue(tables().contains("pending_change_records"))
    }

    @Test fun systemTablesAreNotTouched() {
        val stmts = SessionReset.wipeStatements(listOf("sqlite_sequence", "android_metadata", "room_master_table", "transactions", "pending_change_records"))
        assertEquals(listOf("DELETE FROM `transactions`"), stmts)
    }
}
