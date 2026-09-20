package com.megablok10.app.data

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Страж миграций: ловит забытую миграцию до релиза, а не на телефоне игрока.
 * Схемы лежат в app/schemas (экспортирует Room при сборке).
 */
class MigrationGuardTest {
    private val schemaDir = File("schemas/com.megablok10.app.data.Mb10Database")
    private val currentVersion = 13 // держим в синхроне с @Database(version = …)

    private fun schema(version: Int) = File(schemaDir, "$version.json").also {
        assertTrue("нет экспортированной схемы ${it.path} — соберите проект и закоммитьте app/schemas", it.exists())
    }.readText()

    @Test fun currentSchemaIsExported() {
        assertTrue(schema(currentVersion).contains("\"version\": $currentVersion"))
    }

    @Test fun everyVersionStepFrom13HasMigration() {
        val steps = ALL_MIGRATIONS.map { it.startVersion to it.endVersion }
        assertEquals("миграции должны идти подряд до текущей версии", (12 until currentVersion).map { it to it + 1 }, steps)
    }

    @Test fun outboxMigrationMatchesExportedSchema() {
        val json = schema(13)
        val columns = Regex("`(\\w+)` (INTEGER|TEXT|REAL|BLOB)").findAll(OUTBOX_CREATE_SQL).map { it.groupValues[1] }.toList()
        val table = json.substringAfter("\"tableName\": \"outbox\"").substringBefore("\"indices\"")
        columns.forEach { assertTrue("колонка $it есть в миграции, но не в схеме", table.contains("\"columnName\": \"$it\"")) }
        assertEquals(Regex("\"columnName\"").findAll(table).count(), columns.size)
    }
}
