package com.megablok10.app.log

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Единый журнал приложения: каждая запись идёт и в logcat, и в файл на устройстве (`Android/data/<пакет>/files/logs/`), откуда её можно
 * забрать без компьютера («Настройки → Журнал → Отправить») или через `adb pull`. Нужен для проверок на живых телефонах: после прогона
 * журналы с каждого телефона отдают на разбор.
 *
 * Правила записей:
 *  - формат `дата время.мс уровень/тег [поток] сообщение`; события с полями — `имя ключ=значение ключ=значение` ([event]);
 *  - публичные ключи только в сокращении ([short], 8 символов); код игры, закрытые ключи, тексты сообщений, содержимое предметов и карточек
 *    не пишутся никогда — только длины, идентификаторы и исходы;
 *  - время в локальной зоне телефона с смещением: сопоставлять телефоны между собой удобнее по метке времени, синхронизируйте часы (docs/live-test-plan.md).
 */
object Mb10Log {
    private const val MAX_FILE_BYTES = 2L * 1024 * 1024
    private const val MAX_ROTATED = 7

    @Volatile private var file: RotatingLogFile? = null
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "mb10-log").apply { isDaemon = true } }
    private val stamp = object : ThreadLocal<SimpleDateFormat>() {
        override fun initialValue() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS XXX", Locale.US)
    }

    /** Папка журнала; null, пока [init] не вызван. */
    val directory: File? get() = file?.current?.parentFile

    /** Внутренняя папка приложения — запасной путь, если во внешней писать нельзя. Собирается через «Отправить журнал» или `run-as`. */
    @Volatile private var internalDir: File? = null
    @Volatile var usingFallback: Boolean = false
        private set

    /**
     * Идемпотентно: вызывается при старте процесса. Журнал кладётся во внешнюю папку приложения (`adb pull` без root), но если туда писать
     * нельзя (после переустановки поверх удалённого приложения папка остаётся от прежнего пользователя Android и запись молча не
     * проходит), пишем во внутреннюю — потерять журнал на живой проверке хуже, чем сменить место.
     */
    @Synchronized
    fun init(context: Context) {
        if (file != null) return
        val app = context.applicationContext
        internalDir = File(app.filesDir, "logs")
        val external = app.getExternalFilesDir(null)?.let { File(it, "logs") }
        val chosen = external?.takeIf { canWrite(it) } ?: internalDir!!.also { usingFallback = true }
        file = RotatingLogFile(chosen, MAX_FILE_BYTES, MAX_ROTATED)
        if (usingFallback) w("Mb10Log", "во внешнюю папку писать нельзя (${external?.path}), журнал во внутренней: ${chosen.path}")
    }

    private fun canWrite(dir: File): Boolean = try {
        dir.mkdirs()
        val probe = File(dir, ".probe")
        probe.writeText("ok")
        probe.delete()
        true
    } catch (_: Exception) {
        false
    }

    /** Запись в файл не удалась: переходим на внутреннюю папку и дописываем туда, чтобы строка не пропала. */
    private fun fallbackTo(line: String) {
        val dir = internalDir ?: return
        if (usingFallback) return
        usingFallback = true
        val next = RotatingLogFile(dir, MAX_FILE_BYTES, MAX_ROTATED)
        file = next
        runCatching {
            next.append("${stamp.get()!!.format(Date())} W/Mb10Log [mb10-log] запись во внешнюю папку не удалась, дальше во внутреннюю: ${dir.path}")
            next.append(line)
        }
    }

    fun d(tag: String, msg: String, t: Throwable? = null) = write('D', tag, msg, t)
    fun i(tag: String, msg: String, t: Throwable? = null) = write('I', tag, msg, t)
    fun w(tag: String, msg: String, t: Throwable? = null) = write('W', tag, msg, t)
    fun e(tag: String, msg: String, t: Throwable? = null) = write('E', tag, msg, t)

    /** Событие с полями: `send.outcome to=ab12cd34 outcome=DELIVERED ms=41`. Пустые значения (null) пропускаются. */
    fun event(tag: String, name: String, vararg fields: Pair<String, Any?>) {
        val body = fields.filter { it.second != null }.joinToString(" ") { (k, v) -> "$k=${quote(v.toString())}" }
        write('I', tag, if (body.isEmpty()) name else "$name $body", null)
    }

    /** То же на уровне предупреждения — для отказов и неожиданных исходов. */
    fun warnEvent(tag: String, name: String, vararg fields: Pair<String, Any?>) {
        val body = fields.filter { it.second != null }.joinToString(" ") { (k, v) -> "$k=${quote(v.toString())}" }
        write('W', tag, if (body.isEmpty()) name else "$name $body", null)
    }

    /** Ключ в сокращении для журнала: хватает, чтобы различать игроков, и не раскрывает ключ целиком. */
    fun short(pubKeyB64: String?): String = when {
        pubKeyB64.isNullOrEmpty() -> "-"
        else -> pubKeyB64.filter { it.isLetterOrDigit() }.takeLast(8)
    }

    fun sizeBytes(): Long = file?.totalBytes() ?: 0L

    /** Все файлы журнала, склеенные по порядку. Для экрана экспорта и debug-интента. */
    fun files(): List<File> = file?.allFilesOldestFirst().orEmpty()

    fun clear() {
        executor.execute { file?.clear() }
    }

    /** Ждёт, пока все поставленные записи лягут на диск (перед экспортом и в тестах). */
    fun flush() {
        try { executor.submit {}.get(3, java.util.concurrent.TimeUnit.SECONDS) } catch (_: Exception) { /* не критично */ }
    }

    /** Один zip: журналы + сведения об устройстве (`device.txt`). null — журнала нет. */
    fun exportZip(context: Context, deviceInfo: String): File? {
        flush()
        val list = files()
        val dir = File(context.applicationContext.cacheDir, "log-export").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val out = File(dir, "mb10-logs-${SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())}.zip")
        ZipOutputStream(out.outputStream().buffered()).use { zip ->
            zip.putNextEntry(ZipEntry("device.txt")); zip.write(deviceInfo.toByteArray(Charsets.UTF_8)); zip.closeEntry()
            list.forEach { f -> zip.putNextEntry(ZipEntry(f.name)); f.inputStream().use { it.copyTo(zip) }; zip.closeEntry() }
        }
        return out
    }

    private fun write(level: Char, tag: String, msg: String, t: Throwable?) {
        // logcat — всегда (в JVM-тестах android.util.Log не настоящий, отсюда runCatching)
        runCatching {
            when (level) {
                'D' -> Log.d(tag, msg, t)
                'I' -> Log.i(tag, msg, t)
                'W' -> Log.w(tag, msg, t)
                else -> Log.e(tag, msg, t)
            }
        }
        val f = file ?: return
        val thread = Thread.currentThread().name
        val time = stamp.get()!!.format(Date())
        val trace = t?.let { "\n" + it.stackTraceToString().trimEnd() }.orEmpty()
        val line = "$time $level/$tag [$thread] $msg$trace"
        executor.execute { try { f.append(line) } catch (_: Exception) { fallbackTo(line) } }
    }

    private fun quote(v: String): String = if (v.isEmpty() || v.any(::needsQuotes)) "\"" + v.replace("\"", "'").replace("\n", " ") + "\"" else v

    private fun needsQuotes(c: Char): Boolean = c == ' ' || c == '"' || c == '\n'
}
