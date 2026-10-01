package com.megablok10.netrun.bridge

import org.junit.Test
import org.junit.Assert.*
import java.io.File

/**
 * Тест сверки каталога событий и тревог Моста [events.tsv] с кодом.
 * Проверяет, что каждая строка каталога существует в исходниках как литерал или генерируется динамически.
 * По образцу scripts/e2e/log-contract.tsv и LogContractTest: новые события и виды тревог в каталог перед кодом,
 * затем тест упадёт если что-то поменяется.
 */
class EventCatalogTest {
    private val moduleDir = File(System.getProperty("user.dir")).absolutePath
    private val eventsFile = File(moduleDir, "events.tsv")
    private val srcDir = File(moduleDir).let { File(it, "src/main/kotlin") }

    @Test
    fun catalogFileExists() {
        assertTrue("events.tsv не найден по пути ${eventsFile.absolutePath}", eventsFile.exists())
    }

    @Test
    fun catalogHasValidFormat() {
        assertTrue("events.tsv не файл", eventsFile.isFile)
        val lines = eventsFile.readLines()
        assertTrue("events.tsv пуст", lines.isNotEmpty())

        val header = lines.first()
        assertEquals("Заголовок неправильный", "kind\tsource\tdescription", header)
        assertTrue("Каталог содержит только заголовок, событий нет", lines.size > 1)
    }

    @Test
    fun eachEventInCatalogExistsInSourceCode() {
        val lines = eventsFile.readLines()
        val catalogNames = mutableSetOf<String>()

        for ((idx, line) in lines.drop(1).withIndex()) {
            val parts = line.split('\t')
            assertTrue("Строка ${idx + 2} имеет менее 3 полей", parts.size >= 3)

            val kind = parts[0].trim()
            val source = parts[1].trim()
            assertTrue("Строка ${idx + 2}: kind пуст", kind.isNotEmpty())
            assertTrue("Строка ${idx + 2}: source пуст", source.isNotEmpty())

            catalogNames.add(kind)

            // Проверяем, что событие как строковый литерал существует в коде
            val foundInSource = findLiteralInSource(kind)
            assertTrue(
                "Событие '$kind' из каталога не найдено строковым литералом в $srcDir",
                foundInSource
            )
        }
    }

    @Test
    fun allAlertKindsFromSourceAreInCatalog() {
        val lines = eventsFile.readLines()
        val catalogKinds = lines.drop(1).mapNotNull {
            val parts = it.split('\t')
            if (parts.size >= 1) parts[0].trim() else null
        }.toSet()

        // Ищем все вид тревог, которые код на самом деле создаёт
        // 1. Прямые литералы kind
        val literalKinds = listOf(
            "flatline",           // ValueOps.kt:435
            "auditor_dead",       // Auditor.kt:161
        )

        // 2. Динамически генерируемые виды: "auditor_${v.kind}" где v.kind из Violation
        // Проверяем, что в Violation есть эти kind-значения и они в каталоге
        val dynamicKinds = listOf(
            "auditor_item_owner",    // Violation("item_owner", ...) -> "auditor_" + "item_owner"
            "auditor_deck_items",    // Violation("deck_items", ...) -> "auditor_" + "deck_items"
            "auditor_eddies",        // Violation("eddies", ...) -> "auditor_" + "eddies"
        )

        for (kind in (literalKinds + dynamicKinds)) {
            assertTrue(
                "Вид тревоги '$kind' найден в коде, но не в каталоге events.tsv",
                kind in catalogKinds
            )
        }
    }

    @Test
    fun noDuplicateKindsInCatalog() {
        val lines = eventsFile.readLines()
        val kinds = lines.drop(1).mapNotNull {
            val parts = it.split('\t')
            if (parts.size >= 1) parts[0].trim() else null
        }

        val duplicates = kinds.groupingBy { it }.eachCount().filter { it.value > 1 }
        assertTrue("Дублирующиеся события в каталоге: $duplicates", duplicates.isEmpty())
    }

    @Test
    fun violationKindsCanBeExtractedFromCode() {
        // Убедимся, что в Auditor.kt есть создание Violation с нужными kind-значениями
        val auditorFile = File(srcDir, "com/megablok10/netrun/bridge/Auditor.kt")
        assertTrue("Auditor.kt не найден", auditorFile.exists())

        val content = auditorFile.readText()

        // Проверяем, что code создаёт Violation с этими kind
        assertTrue("Auditor должен создавать Violation(\"item_owner\",...)",
            content.contains("""Violation("item_owner""""))
        assertTrue("Auditor должен создавать Violation(\"deck_items\",...)",
            content.contains("""Violation("deck_items""""))
        assertTrue("Auditor должен создавать Violation(\"eddies\",...)",
            content.contains("""Violation("eddies""""))
    }

    private fun findLiteralInSource(name: String): Boolean {
        if (!srcDir.isDirectory) return false

        return srcDir.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .any { file ->
                val text = file.readText()
                // Тревоги аудитора собираются как "auditor_${v.kind}": ищем сам вид нарушения в Violation("…").
                text.contains("\"$name\"") ||
                    (name.startsWith(AUDITOR_PREFIX) && text.contains("Violation(\"${name.removePrefix(AUDITOR_PREFIX)}\""))
            }
    }

    private companion object {
        const val AUDITOR_PREFIX = "auditor_"
    }
}
