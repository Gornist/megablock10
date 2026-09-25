package com.megablok10.app.log

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Стенд e2e (scripts/e2e) читает вывод приложения: события журнала (`sync.unreachable`, `chat.recv`) и строки `MB10DBG`.
 * Раньше переименование в коде ломало стенд молча: heal_host_reach искал «CollectorClient.*недоступен», которого код давно не
 * писал, и не сработал ни разу (25.09). Контракт — scripts/e2e/log-contract.tsv; этот тест сверяет его с кодом и со стендом.
 */
class LogContractTest {
    private val root = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "settings.gradle.kts").exists() }
    private val contract = File(root, "scripts/e2e/log-contract.tsv").readLines()
        .filter { it.isNotBlank() && !it.startsWith("#") }
        .map { line -> line.split('\t').also { require(it.size == 2) { "log-contract.tsv: не «тег<TAB>строка»: $line" } }.let { it[0] to it[1] } }
    private val sources = listOf("app/src/main/java", "app/src/debug/java", "kit/src/main/kotlin")
        .flatMap { File(root, it).walk().filter { f -> f.extension == "kt" }.toList() }
        .associateWith { it.readText() }
    private val scripts = File(root, "scripts/e2e").walk().filter { it.extension == "sh" }.associateWith { it.readText() }

    @Test fun everyContractLineIsWrittenByTheApp() {
        val missing = contract.filter { (tag, text) ->
            // Строка должна стоять в том же файле, где объявлен тег: иначе переезд события в другой класс (с другим тегом) не заметить.
            sources.values.none { src -> text in src && (tag == "*" || "\"$tag\"" in src) }
        }
        assertTrue("код приложения не пишет строк, которые ищет стенд (scripts/e2e/log-contract.tsv): $missing", missing.isEmpty())
    }

    @Test fun everyContractLineIsUsedByTheStand() {
        val unused = contract.filter { (_, text) -> scripts.values.none { text in it } }
        assertTrue("строки контракта, которых стенд больше не ищет, — убрать из log-contract.tsv: $unused", unused.isEmpty())
    }

    @Test fun everyLogcatTagReadByTheStandIsInTheContract() {
        val tags = contract.map { it.first }.toSet()
        val used = scripts.flatMap { (file, text) ->
            Regex("""logcat\b[^|\n]*?-s\s+(\w+)""").findAll(text).map { "${file.name}: ${it.groupValues[1]}" to it.groupValues[1] }.toList()
        }
        val unknown = used.filter { it.second !in tags }.map { it.first }
        assertTrue("стенд читает теги logcat, которых нет в scripts/e2e/log-contract.tsv: $unknown", unknown.isEmpty())
    }
}
