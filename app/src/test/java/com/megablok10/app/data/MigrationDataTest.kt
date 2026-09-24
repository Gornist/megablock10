package com.megablok10.app.data

import androidx.sqlite.db.SupportSQLiteDatabase
import java.io.File
import java.lang.reflect.Proxy
import java.sql.Connection
import java.sql.DriverManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Прогон настоящих миграций Room на настоящем SQLite (sqlite-jdbc) с данными игрока: данные переживают миграцию, а получившаяся
 * таблица совпадает со схемой из экспорта. Сама `Migration.migrate` вызывается как есть — ей отдаётся тонкая обёртка над JDBC-соединением,
 * умеющая только execSQL (этого хватает миграциям на чистом SQL; если миграции понадобится большее — тест сразу скажет об этом ошибкой).
 * Стартовая база (версия 12) собирается из экспортированной схемы 13 без таблицы outbox — 12→13 добавила только её.
 */
class MigrationDataTest {
    private val schemaDir = File("schemas/com.megablok10.app.data.Mb10Database")
    private lateinit var conn: Connection

    @Before fun open() { conn = DriverManager.getConnection("jdbc:sqlite::memory:") }
    @After fun close() { conn.close() }

    /** таблица → createSql из экспорта версии [version] (с подставленным именем таблицы). */
    private fun schemaTables(version: Int): Map<String, String> {
        val json = File(schemaDir, "$version.json").readText()
        val re = Regex("\"tableName\":\\s*\"(\\w+)\",\\s*\"createSql\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
        return re.findAll(json).associate { m -> m.groupValues[1] to m.groupValues[2].replace("\${TABLE_NAME}", m.groupValues[1]) }
    }

    private fun sql(q: String) { conn.createStatement().use { it.execute(q) } }
    private fun scalar(q: String): String? = conn.createStatement().use { st -> st.executeQuery(q).use { rs -> if (rs.next()) rs.getString(1) else null } }
    private fun columns(table: String): List<String> = conn.createStatement().use { st ->
        st.executeQuery("PRAGMA table_info($table)").use { rs -> buildList { while (rs.next()) add("${rs.getString("name")}:${rs.getString("type")}:${rs.getInt("notnull")}:${rs.getInt("pk")}") } }
    }
    private fun indexNames(table: String): List<String> = conn.createStatement().use { st ->
        st.executeQuery("PRAGMA index_list($table)").use { rs -> buildList { while (rs.next()) add(rs.getString("name")) } }
    }

    /** Минимальный SupportSQLiteDatabase: только execSQL, всё остальное — явная ошибка. */
    private fun supportDb(): SupportSQLiteDatabase = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SupportSQLiteDatabase::class.java)) { _, method, args ->
        when (method.name) {
            "execSQL" -> { sql(args[0] as String); null }
            else -> throw UnsupportedOperationException("миграция использует ${method.name}(), а тест умеет только execSQL")
        }
    } as SupportSQLiteDatabase

    @Test fun migration12to13KeepsPlayerDataAndCreatesOutbox() {
        val v13 = schemaTables(13)
        assertTrue("в экспорте схемы 13 нет таблицы outbox", "outbox" in v13)
        // версия 12: всё, кроме outbox
        v13.filterKeys { it != "outbox" }.values.forEach(::sql)
        sql("INSERT INTO transactions (id, counterpartyPubKeyB64, amount, memo, timestamp, status) VALUES ('tx-1', 'pk-bob', -300, 'за шард', 1000, 'CONFIRMED')")
        sql("INSERT INTO container_breaches (containerId, lastRewardedAt) VALUES ('arasaka-404', 2000)")
        sql("INSERT INTO consumed_tokens (token, consumedAt) VALUES ('ram-token-1', 3000)")
        assertEquals("outbox ещё нет", null, scalar("SELECT name FROM sqlite_master WHERE name = 'outbox'"))

        ALL_MIGRATIONS.filter { it.startVersion == 12 }.forEach { it.migrate(supportDb()) }

        // данные игрока целы
        assertEquals("-300", scalar("SELECT amount FROM transactions WHERE id = 'tx-1'"))
        assertEquals("2000", scalar("SELECT lastRewardedAt FROM container_breaches WHERE containerId = 'arasaka-404'"))
        assertEquals("3000", scalar("SELECT consumedAt FROM consumed_tokens WHERE token = 'ram-token-1'"))
        // outbox появилась и совпадает со схемой из экспорта
        val expected = DriverManager.getConnection("jdbc:sqlite::memory:").use { ref ->
            ref.createStatement().use { it.execute(v13.getValue("outbox")) }
            ref.createStatement().use { st -> st.executeQuery("PRAGMA table_info(outbox)").use { rs -> buildList { while (rs.next()) add("${rs.getString("name")}:${rs.getString("type")}:${rs.getInt("notnull")}:${rs.getInt("pk")}") } } }
        }
        assertEquals(expected, columns("outbox"))
        // и в неё можно писать
        sql("INSERT INTO outbox (toPubKeyB64, wireLine, createdAt, attempts, nextAttemptAt) VALUES ('pk-bob', 'MB10CHAT:v1:...', 1, 0, 0)")
        assertEquals("1", scalar("SELECT COUNT(*) FROM outbox"))
    }

    @Test fun migrationIsIdempotentOnAlreadyMigratedDatabase() {
        // Повторный запуск (например, после прерванной миграции) не должен падать и терять данные: CREATE TABLE IF NOT EXISTS.
        schemaTables(13).values.forEach(::sql)
        sql("INSERT INTO outbox (toPubKeyB64, wireLine, createdAt, attempts, nextAttemptAt) VALUES ('pk', 'line', 1, 0, 0)")
        ALL_MIGRATIONS.filter { it.startVersion == 12 }.forEach { it.migrate(supportDb()) }
        assertEquals("1", scalar("SELECT COUNT(*) FROM outbox"))
    }

    @Test fun migration13to14AddsIndexesWithoutTouchingData() {
        schemaTables(13).values.forEach(::sql)
        sql("INSERT INTO transactions (id, counterpartyPubKeyB64, amount, memo, timestamp, status) VALUES ('tx-1', 'pk-bob', -300, 'за шард', 1000, 'CONFIRMED')")
        sql("INSERT INTO outbox (toPubKeyB64, wireLine, createdAt, attempts, nextAttemptAt) VALUES ('pk-bob', 'MB10CHAT:v1:...', 1, 0, 0)")
        assertTrue("до миграции индекса на transactions.timestamp быть не должно", indexNames("transactions").none { it.contains("timestamp") })
        assertTrue("до миграции индекса на outbox.nextAttemptAt быть не должно", indexNames("outbox").none { it.contains("nextAttemptAt") })

        ALL_MIGRATIONS.filter { it.startVersion == 13 }.forEach { it.migrate(supportDb()) }

        assertTrue("миграция 13→14 должна создать индекс на transactions.timestamp", "index_transactions_timestamp" in indexNames("transactions"))
        assertTrue("миграция 13→14 должна создать индекс на outbox.nextAttemptAt", "index_outbox_nextAttemptAt" in indexNames("outbox"))
        // данные не затронуты — миграция только добавляет индексы
        assertEquals("-300", scalar("SELECT amount FROM transactions WHERE id = 'tx-1'"))
        assertEquals("1", scalar("SELECT COUNT(*) FROM outbox"))
    }

    @Test fun migration13to14IsIdempotentOnAlreadyMigratedDatabase() {
        // Повторный запуск (например, после прерванной миграции) не должен падать — CREATE INDEX IF NOT EXISTS.
        schemaTables(13).values.forEach(::sql)
        ALL_MIGRATIONS.filter { it.startVersion == 13 }.forEach { it.migrate(supportDb()) }
        ALL_MIGRATIONS.filter { it.startVersion == 13 }.forEach { it.migrate(supportDb()) }
        assertEquals(1, indexNames("transactions").count { it == "index_transactions_timestamp" })
    }

    @Test fun migration14to15AddsSeqCounterWithoutTouchingData() {
        schemaTables(14).values.forEach(::sql)
        sql("INSERT INTO transactions (id, counterpartyPubKeyB64, amount, memo, timestamp, status) VALUES ('tx-1', 'pk-bob', -300, 'за шард', 1000, 'CONFIRMED')")
        sql("INSERT INTO pending_change_records (id, subjectKeyB64, seq, happenedAt, field, oldValue, newValue, reason, sourceRef, actor, signature) VALUES ('r-1', 'me', 41, 5, 'balance', '0', '10', 'SHARD_SCAN', NULL, 'me', 'sig')")

        ALL_MIGRATIONS.filter { it.startVersion == 14 }.forEach { it.migrate(supportDb()) }
        ALL_MIGRATIONS.filter { it.startVersion == 14 }.forEach { it.migrate(supportDb()) }   // повтор после прерванной миграции не падает

        assertEquals("таблица счётчика совпадает со схемой 15", listOf("name:TEXT:1:1", "value:INTEGER:1:0"), columns("sequences"))
        assertEquals("счётчик пуст: начальное значение берёт первая выдача номера", "0", scalar("SELECT COUNT(*) FROM sequences"))
        assertEquals("-300", scalar("SELECT amount FROM transactions WHERE id = 'tx-1'"))
        assertEquals("41", scalar("SELECT seq FROM pending_change_records WHERE id = 'r-1'"))
    }

    @Test fun seqCounterMigrationMatchesExportedSchema() {
        assertEquals(schemaTables(15)["sequences"], SEQUENCES_CREATE_SQL)
    }

    @Test fun exportedSchemaHasEveryTableOfTheCurrentVersion() {
        val tables = schemaTables(15)
        assertTrue("regex схемы не нашёл таблиц (изменился формат экспорта?)", tables.size >= 10)
        tables.values.forEach(::sql)   // каждый createSql — валидный SQLite
        assertEquals(tables.size.toString(), scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
    }
}
