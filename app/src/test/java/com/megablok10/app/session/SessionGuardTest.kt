package com.megablok10.app.session

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * B3: запускать и останавливать фоновую работу — только через SessionController (его адаптер SessionActions — в di/AppGraph).
 * Новый вызов mesh.start/stop, запуск синка или MeshForegroundService.start где-то ещё — снова «размазанный» запуск, от которого
 * уходили (сеть без синка, сервис из фона роняет процесс).
 */
class SessionGuardTest {
    private val root = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "settings.gradle.kts").exists() }
    private val allowed = setOf("session/SessionController.kt", "di/AppGraph.kt", "presence/MeshForegroundService.kt")
    private val forbidden = listOf(
        Regex("""\bmesh\.(start|stop)\("""),
        Regex("""MeshForegroundService\.start\("""),
        Regex("""\bcollectorSync\.run\("""),
        Regex("""\bstartCollectorSync\("""),
    )

    @Test fun onlyTheControllerStartsBackgroundWork() {
        val sources = listOf("app/src/main/java", "app/src/debug/java").flatMap { File(root, it).walk().filter { f -> f.extension == "kt" }.toList() }
        val offenders = sources.filter { f -> allowed.none { f.path.endsWith(it) } }.flatMap { f ->
            f.readLines().mapIndexedNotNull { i, line -> if (forbidden.any { it.containsMatchIn(line) }) "${f.relativeTo(root)}:${i + 1}: ${line.trim()}" else null }
        }
        assertEquals("фоновую работу запускает только SessionController", emptyList<String>(), offenders)
    }
}
