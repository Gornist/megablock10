package com.megablok10.netrun.bridge.collector

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Сверка каталога быстрых событий `netrun-bridge/world-events.tsv` с кодом, таблицей раздела 3 контракта
 * (`docs/netrun-world-records.md`) и списком видов, которые принимает коллектор (`admin-web/server/src/lib/worldEvents.ts`).
 * Новый вид — сначала в каталог и в приём коллектора: иначе Мост слал бы события, которые приём отбросит как невалидные.
 * Каталог тревог аудитора и MasterOps — отдельный файл `events.tsv` ([com.megablok10.netrun.bridge.EventCatalogTest]).
 */
class WorldEventCatalogTest {
    private val moduleDir = File(System.getProperty("user.dir")).absoluteFile
    private val catalog = File(moduleDir, "world-events.tsv")
    private val repo = moduleDir.parentFile

    private fun catalogRows(): List<List<String>> = catalog.readLines().drop(1).filter { it.isNotBlank() }.map { it.split('\t') }

    @Test fun catalogHasHeaderAndEveryRowHasThreeFields() {
        assertEquals("kind\tsource\tdescription", catalog.readLines().first())
        val rows = catalogRows()
        assertTrue(rows.isNotEmpty())
        assertTrue(rows.toString(), rows.all { it.size == 3 && it.all(String::isNotBlank) })
        assertEquals("дубли в каталоге", rows.size, rows.map { it[0] }.toSet().size)
    }

    @Test fun catalogKindsAreExactlyTheKindsOfTheCode() {
        assertEquals(FastKinds.ALL.toSet(), catalogRows().map { it[0] }.toSet())
        val source = File(moduleDir, "src/main/kotlin/com/megablok10/netrun/bridge/collector/WorldFastEvents.kt").readText()
        for (kind in FastKinds.ALL) assertTrue("вид $kind не найден литералом в WorldFastEvents.kt", "\"$kind\"" in source)
    }

    @Test fun contractTableOfSectionThreeListsTheSameKinds() {
        val doc = File(repo, "docs/netrun-world-records.md")
        assumeTrue("нет ${doc.path}: Мост собран без репозитория", doc.isFile)
        val section = doc.readText().substringAfter("## 3. ").substringBefore("## 4. ")
        val inTable = Regex("""^\| `([a-z.]+)` \|""", RegexOption.MULTILINE).findAll(section).map { it.groupValues[1] }.toSet() - "kind" // «kind» — заголовок таблицы
        assertEquals(FastKinds.ALL.toSet(), inTable)
    }

    @Test fun collectorAcceptsExactlyTheseKinds() {
        val ts = File(repo, "admin-web/server/src/lib/worldEvents.ts")
        assumeTrue("нет ${ts.path}: коллектор рядом не лежит", ts.isFile)
        val list = Regex("""WORLD_EVENT_KINDS\s*=\s*\[([^\]]*)]""").find(ts.readText())?.groupValues?.get(1)
        assertTrue("WORLD_EVENT_KINDS не найден в worldEvents.ts", list != null)
        val kinds = Regex(""""([a-z.]+)"""").findAll(list!!).map { it.groupValues[1] }.toSet()
        assertEquals("виды Моста и приёма коллектора разошлись", kinds, FastKinds.ALL.toSet())
    }
}
