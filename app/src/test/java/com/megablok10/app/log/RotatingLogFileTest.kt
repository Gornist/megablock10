package com.megablok10.app.log

import java.io.File
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

class RotatingLogFileTest {
    private fun tempDir(): File = kotlin.io.path.createTempDirectory("mb10log").toFile()

    @Test
    fun `строки пишутся по порядку в текущий файл`() {
        val dir = tempDir()
        val log = RotatingLogFile(dir, 10_000, 3)
        log.append("первая"); log.append("вторая")
        assertEquals(listOf("первая", "вторая"), log.current.readLines())
        log.close()
    }

    @Test
    fun `при превышении размера файл ротируется, старые вытесняются`() {
        val dir = tempDir()
        val log = RotatingLogFile(dir, 100, 2)
        repeat(60) { log.append("строка-$it-" + "x".repeat(20)) }
        val files = log.allFilesOldestFirst()
        // два старых и текущий
        assertEquals(3, files.size)
        // порядок: от старых к новым, последняя запись — в текущем
        assertTrue(files.last().readLines().last().startsWith("строка-59-"))
        // самые старые записи вытеснены
        assertTrue(files.flatMap { it.readLines() }.none { it.startsWith("строка-0-") })
        // каждый файл не больше лимита
        assertTrue(files.all { it.length() <= 100 })
        log.close()
    }

    @Test
    fun `после переоткрытия дописывает в тот же файл`() {
        val dir = tempDir()
        RotatingLogFile(dir, 10_000, 3).also { it.append("до"); it.close() }
        val again = RotatingLogFile(dir, 10_000, 3)
        again.append("после")
        assertEquals(listOf("до", "после"), again.current.readLines())
        again.close()
    }

    @Test
    fun `clear удаляет все файлы журнала`() {
        val dir = tempDir()
        val log = RotatingLogFile(dir, 50, 2)
        repeat(20) { log.append("запись-$it-xxxxxxxxxx") }
        log.clear()
        assertTrue(log.allFilesOldestFirst().isEmpty())
        log.append("новая")
        assertEquals(listOf("новая"), log.current.readLines())
        log.close()
    }
}
