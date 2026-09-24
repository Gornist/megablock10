package com.megablok10.kit.log

import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.io.Writer

/**
 * Файл журнала с ротацией, без Android-зависимостей (проверяется JVM-тестами). Пишет в `<prefix>-current.log`; когда он вырастает
 * до [maxBytes], переименовывает его в `<prefix>-<n>.log` и начинает новый, держит не больше [maxFiles] старых. Каждая строка
 * сбрасывается на диск сразу: при падении приложения последние записи должны остаться.
 *
 * [prefix] — имя приложения в именах файлов (в Мегаблоке `mb10`: по `mb10-*.log` журналы забирает стенд e2e и `adb pull`).
 *
 * Не потокобезопасен сам по себе: вызывающий пишет из одного потока (в Мегаблоке — однопоточный исполнитель Mb10Log).
 */
class RotatingLogFile(private val dir: File, private val maxBytes: Long, private val maxFiles: Int, private val prefix: String) {
    private var writer: Writer? = null
    private var written = 0L
    private val rotatedName = Regex(Regex.escape(prefix) + "-(\\d+)\\.log")

    val current: File get() = File(dir, "$prefix-current.log")

    fun append(line: String) {
        val w = writer ?: open()
        val bytes = line.toByteArray(Charsets.UTF_8).size + 1
        if (written > 0 && written + bytes > maxBytes) {
            rotate()
            return append(line)
        }
        w.write(line)
        w.write("\n")
        w.flush()
        written += bytes
    }

    /** Все файлы журнала от старых к новым (для экспорта). */
    fun allFilesOldestFirst(): List<File> {
        val rotated = dir.listFiles { f -> rotatedName.matches(f.name) }.orEmpty().sortedBy { rotatedIndex(it) }
        return rotated + listOfNotNull(current.takeIf { it.exists() })
    }

    fun totalBytes(): Long = allFilesOldestFirst().sumOf { it.length() }

    fun clear() {
        close()
        dir.listFiles { f -> f.name == current.name || rotatedName.matches(f.name) }?.forEach { it.delete() }
        written = 0
    }

    fun close() {
        try { writer?.close() } catch (_: Exception) { /* уже закрыт */ }
        writer = null
    }

    private fun open(): Writer {
        dir.mkdirs()
        val f = current
        written = if (f.exists()) f.length() else 0L
        return OutputStreamWriter(FileOutputStream(f, true), Charsets.UTF_8).also { writer = it }
    }

    private fun rotate() {
        close()
        val next = (dir.listFiles { f -> rotatedName.matches(f.name) }.orEmpty().maxOfOrNull { rotatedIndex(it) } ?: 0) + 1
        current.renameTo(File(dir, "$prefix-$next.log"))
        val rotated = dir.listFiles { f -> rotatedName.matches(f.name) }.orEmpty().sortedBy { rotatedIndex(it) }
        rotated.dropLast(maxFiles).forEach { it.delete() }
        written = 0
    }

    private fun rotatedIndex(f: File): Int = rotatedName.matchEntire(f.name)?.groupValues?.get(1)?.toIntOrNull() ?: 0
}
