package com.megablok10.kit.net

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import java.io.BufferedReader
import java.io.InputStream
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Один протокол, который слушает [LineServer]: распознаёт свою строку ([decode] вернул не null) и обрабатывает её. [kind] —
 * короткое имя для журнала (`chat`, `call`…). Обработчик не должен блокировать надолго: тяжёлую работу запускайте в своём
 * скоупе, сервер уже ждёт следующее соединение.
 */
class LineRoute<T : Any>(val kind: String, private val decode: (String) -> T?, private val handle: (T) -> Unit) {
    /** Действие для этой строки, если она наша; null — не наш протокол. */
    internal fun match(line: String): (() -> Unit)? = decode(line)?.let { value -> { handle(value) } }
}

/**
 * Приём строк по TCP: порт выбирает ОС (0 — свободный), одно соединение = одна строка (см. [LineSocketClient]), дальше
 * сокет закрывается — без долгоживущих соединений и их учёта. Несколько протоколов делят один сервер и порт: строку забирает
 * первый [LineRoute], который её распознал (обычно по магическому префиксу `МАГИЯ:vN:`). Нераспознанная строка уходит в
 * [onUnrecognized] (например, чтобы сказать игроку, что рядом телефон с другой версией протокола).
 *
 * Защита от мусора в сети: строка длиннее [maxLineChars] отбрасывается не читая до конца, молчащий клиент отваливается по
 * [readTimeoutMs], а любой сбой одного соединения — таймаут, обрыв, исключение из обработчика — остаётся внутри него и не
 * роняет ни сервер, ни приложение.
 *
 * [tag] — тег в журнале (в Мегаблоке `ChatServer`: по нему разбирают журналы живых проверок).
 */
class LineServer(
    private val routes: List<LineRoute<*>>,
    private val onUnrecognized: (String) -> Unit = {},
    private val log: KitLog = NoopLog,
    private val tag: String = "LineServer",
    private val maxLineChars: Int = DEFAULT_MAX_LINE_CHARS,
    private val readTimeoutMs: Int = 5000,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    @Volatile private var serverSocket: ServerSocket? = null
    private var job: Job? = null

    /** Порт, на котором сервер слушает; -1 — не запущен. */
    val port: Int get() = serverSocket?.localPort ?: -1

    /** Открывает порт сразу (вызывающий может тут же объявить его в сети) и принимает соединения в [scope]. */
    fun start(scope: CoroutineScope) {
        val socket = ServerSocket(0)
        serverSocket = socket
        log.event(tag, "server.listen", "port" to socket.localPort)
        job = scope.launch(io) {
            while (isActive) {
                val client = try {
                    socket.accept()
                } catch (e: Exception) {
                    break
                }
                launch(io) { handleClient(client) }
            }
        }
    }

    fun stop() {
        job?.cancel()
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            // сокет мог уже закрыться сам — не наша забота на остановке
        }
        serverSocket = null
        job = null
    }

    private fun handleClient(socket: Socket) {
        try {
            socket.use {
                it.soTimeout = readTimeoutMs
                val remote = it.inetAddress?.hostAddress
                val line = readBoundedLine(it.getInputStream(), maxLineChars)
                if (line == null) {
                    log.warnEvent(tag, "server.empty_or_oversize", "from" to remote)
                    return
                }
                dispatch(line, remote)
            }
        } catch (e: Exception) {
            log.w(tag, "входящее соединение отброшено: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun dispatch(line: String, remote: String?) {
        for (route in routes) {
            val action = route.match(line) ?: continue
            // Что именно пришло — только вид и длина: тексты и карточки в журнал не попадают.
            log.event(tag, "server.recv", "from" to remote, "kind" to route.kind, "chars" to line.length)
            action()
            return
        }
        log.event(tag, "server.recv", "from" to remote, "kind" to "unknown", "chars" to line.length)
        log.warnEvent(tag, "server.incompatible_line", "from" to remote, "head" to line.take(24))
        onUnrecognized(line)
    }

    companion object {
        /** Самая длинная легитимная строка у Мегаблока — SDP-предложение звонка (единицы КБ в base64); всё, что больше, — мусор или попытка забить память. */
        const val DEFAULT_MAX_LINE_CHARS = 256 * 1024
    }
}

/**
 * Читает одну строку до '\n', но не больше [maxChars] символов: BufferedReader.readLine() накапливал бы строку без границы,
 * пока клиент шлёт данные без перевода строки. null — поток кончился без данных, либо строка длиннее лимита (отбрасываем
 * целиком). Завершающий '\r' срезается.
 */
fun readBoundedLine(input: InputStream, maxChars: Int): String? {
    val reader = BufferedReader(InputStreamReader(input, Charsets.UTF_8))
    val sb = StringBuilder()
    while (true) {
        val c = reader.read()
        if (c == -1) return if (sb.isEmpty()) null else sb.toString()
        if (c == '\n'.code) return sb.toString().trimEnd('\r')
        if (sb.length >= maxChars) return null
        sb.append(c.toChar())
    }
}
