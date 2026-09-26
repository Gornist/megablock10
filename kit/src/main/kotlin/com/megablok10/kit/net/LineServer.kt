package com.megablok10.kit.net

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import java.io.BufferedReader
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.BindException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Один протокол, который слушает [LineServer]: распознаёт свою строку ([decode] вернул не null) и обрабатывает её. [kind] —
 * короткое имя для журнала (`chat`, `call`…). Отправителю строки в конверте сервер отвечает `ok` только после того, как
 * [handle] вернулся: всё, после чего можно сказать «доставлено» (у Мегаблока — сохранение в Room), делайте в нём, остальное
 * (звук, уведомления) — в своём скоупе. Исключение из [handle] — без ответа: отправитель считает, что строка могла дойти.
 */
class LineRoute<T : Any>(val kind: String, private val decode: (String) -> T?, private val handle: suspend (T) -> Unit) {
    /** Действие для этой строки, если она наша; null — не наш протокол. */
    internal fun match(line: String): (suspend () -> Unit)? = decode(line)?.let { value -> { handle(value) } }
}

/**
 * Приём строк по TCP на порту [preferredPort] (0 — любой свободный; занят — тоже любой, с событием `server.listen_fallback`:
 * фиксированный порт делает адрес устройства постоянным между перезапусками, docs/refactor-plan.md, D1), одно соединение = одна
 * строка (см. [LineSocketClient]), дальше
 * сокет закрывается — без долгоживущих соединений и их учёта. Несколько протоколов делят один сервер и порт: строку забирает
 * первый [LineRoute], который её распознал (обычно по магическому префиксу `МАГИЯ:vN:`). Нераспознанная строка уходит в
 * [onUnrecognized] (например, чтобы сказать игроку, что рядом телефон с другой версией протокола).
 *
 * Защита от мусора в сети: строка длиннее [maxLineChars] отбрасывается не читая до конца, молчащий клиент отваливается по
 * [readTimeoutMs], а любой сбой одного соединения — таймаут, обрыв, исключение из обработчика — остаётся внутри него и не
 * роняет ни сервер, ни приложение.
 *
 * Строка в конверте ([LineEnvelope], D2): сервер проверяет, что она для [identityKey], обрабатывает и отвечает [LineAck]:
 * `ok` — после обработки (не дольше [handleTimeoutMs], дольше — без ответа), `wrong` — строка другому игроку, не обработана,
 * `reject` — своя, но не принята (нет личности, непонятная строка). По конверту и адресу соединения — [onHeard]: где слушает
 * отправитель. Строка без конверта (отправитель на старой версии) обрабатывается как раньше, без проверки и ответа.
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
    private val preferredPort: Int = 0,
    private val identityKey: () -> String? = { null },
    private val onHeard: (key: String, host: String, port: Int) -> Unit = { _, _, _ -> },
    private val handleTimeoutMs: Long = 3_000,
    private val reopenDelayMs: Long = 1_000,
) {
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var stopped = false
    private var job: Job? = null
    private var scope: CoroutineScope? = null

    /** Порт, на котором сервер слушает; -1 — не запущен. */
    val port: Int get() = serverSocket?.localPort ?: -1

    /**
     * Открывает порт сразу (вызывающий может тут же объявить его в сети) и принимает соединения в [scope].
     *
     * Слушающий сокет может умереть и без [stop]: Android уничтожает сокеты сети, которая пропала (процесс привязан к Wi-Fi площадки),
     * — e2e run 36209401543: после выключения/включения Wi-Fi у получателя его сервер больше не принял ни одного соединения, а
     * цикл приёма молча вышел. Теперь сбой приёма — событие `server.accept_failed` и тот же порт заново через [reopenDelayMs];
     * при смене сети его можно переоткрыть и заранее ([relisten]).
     */
    fun start(scope: CoroutineScope) {
        stopped = false
        this.scope = scope
        reopen(reason = "start")
        job = scope.launch(io) {
            while (isActive && !stopped) {
                val client = serverSocket?.let { acceptOrRecover(it) }
                if (client != null) launch(io) { handleClient(client) }
            }
        }
    }

    /** Соединение или null: сокет переоткрыт [relisten] (не сбой), остановлен, либо умер — тогда тот же порт заново после паузы. */
    private suspend fun acceptOrRecover(listening: ServerSocket): Socket? = try {
        listening.accept()
    } catch (e: Exception) {
        if (!stopped && serverSocket === listening) {
            log.warnEvent(tag, "server.accept_failed", "error" to e.javaClass.simpleName, "msg" to e.message)
            delay(reopenDelayMs)
            if (!stopped && serverSocket === listening) runCatching { reopen(reason = "accept_failed") }
                .onFailure { log.warnEvent(tag, "server.reopen_failed", "error" to it.javaClass.simpleName) }
        }
        null
    }

    /** Закрыть и снова открыть слушающий сокет на том же порту (смена сети: старый мог принадлежать пропавшей). Принятые соединения не трогает. */
    fun relisten() {
        if (stopped || serverSocket == null) return
        runCatching { reopen(reason = "network") }.onFailure { log.warnEvent(tag, "server.reopen_failed", "error" to it.javaClass.simpleName) }
    }

    @Synchronized
    private fun reopen(reason: String) {
        if (stopped && reason != "start") return
        try { serverSocket?.close() } catch (e: Exception) { /* уже закрыт */ }
        val socket = open()
        serverSocket = socket
        log.event(tag, "server.listen", "port" to socket.localPort, "reason" to reason)
    }

    /** Только для тестов: убить слушающий сокет «снаружи», как это делает Android при потере сети. */
    internal fun killListeningSocketForTest() { serverSocket?.close() }

    /**
     * SO_REUSEADDR — чтобы перезапущенный процесс снова занял свой порт, пока соединения прошлого висят в TIME_WAIT. Порт занят
     * чем-то живым — берём любой: устройство останется доступным (порт объявляется в NSD и серверу), просто не по постоянному адресу.
     */
    private fun open(): ServerSocket {
        if (preferredPort > 0) {
            val socket = ServerSocket().apply { reuseAddress = true }
            try {
                socket.bind(InetSocketAddress(preferredPort))
                return socket
            } catch (e: BindException) {
                socket.close()
                log.warnEvent(tag, "server.listen_fallback", "wanted" to preferredPort, "error" to e.message)
            }
        }
        return ServerSocket(0)
    }

    fun stop() {
        stopped = true
        job?.cancel()
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            // сокет мог уже закрыться сам — не наша забота на остановке
        }
        serverSocket = null
        job = null
    }

    private suspend fun handleClient(socket: Socket) {
        try {
            socket.use {
                it.soTimeout = readTimeoutMs
                val remote = it.inetAddress?.hostAddress
                val line = readBoundedLine(it.getInputStream(), maxLineChars)
                if (line == null) {
                    log.warnEvent(tag, "server.empty_or_oversize", "from" to remote)
                    return
                }
                if (LineEnvelope.isEnvelope(line)) handleEnvelope(it, line, remote) else dispatch(line, remote)
            }
        } catch (e: Exception) {
            log.w(tag, "входящее соединение отброшено: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private suspend fun handleEnvelope(socket: Socket, raw: String, remote: String?) {
        val envelope = LineEnvelope.decode(raw) ?: run {
            // конверт другой версии: сказать игроку, что рядом телефон с другим приложением (onUnrecognized)
            log.warnEvent(tag, "server.incompatible_line", "from" to remote, "head" to raw.take(24))
            onUnrecognized(raw)
            return
        }
        if (envelope.from.isNotEmpty() && envelope.fromPort > 0 && remote != null) onHeard(envelope.from, remote, envelope.fromPort)
        val me = identityKey()
        if (me == null || envelope.to != me) {
            val status = if (me == null) LineAck.Status.REJECT else LineAck.Status.WRONG
            log.warnEvent(tag, "server.not_for_me", "from" to remote, "to" to envelope.to.take(8), "status" to status.wire)
            reply(socket, LineAck(status, me.orEmpty()))
            return
        }
        // Обработка — в скоупе сервера, а не этого соединения: не уложилась в handleTimeoutMs — отвечать нечего (отправитель
        // сочтёт «могло дойти»), но и бросать её на полпути нельзя.
        // runCatching — упавший обработчик не должен ронять скоуп сервера (async передал бы сбой родителю).
        val work = (scope ?: return).async(io) { runCatching { dispatch(envelope.line, remote) } }
        val result = withTimeoutOrNull(handleTimeoutMs) { work.await() }
        when {
            result == null -> log.warnEvent(tag, "server.handle_timeout", "from" to remote, "ms" to handleTimeoutMs)
            result.isFailure -> throw checkNotNull(result.exceptionOrNull()) // без ответа: могло обработаться частично
            result.getOrThrow() -> reply(socket, LineAck(LineAck.Status.OK, me))
            else -> reply(socket, LineAck(LineAck.Status.REJECT, me))
        }
    }

    private fun reply(socket: Socket, ack: LineAck) {
        val writer = OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)
        writer.write(ack.encode())
        writer.write("\n")
        writer.flush()
    }

    /** true — строку забрал и обработал один из [routes]; false — непонятная строка ([onUnrecognized]). */
    private suspend fun dispatch(line: String, remote: String?): Boolean {
        for (route in routes) {
            val action = route.match(line) ?: continue
            // Что именно пришло — только вид и длина: тексты и карточки в журнал не попадают.
            log.event(tag, "server.recv", "from" to remote, "kind" to route.kind, "chars" to line.length)
            action()
            return true
        }
        log.event(tag, "server.recv", "from" to remote, "kind" to "unknown", "chars" to line.length)
        log.warnEvent(tag, "server.incompatible_line", "from" to remote, "head" to line.take(24))
        onUnrecognized(line)
        return false
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
