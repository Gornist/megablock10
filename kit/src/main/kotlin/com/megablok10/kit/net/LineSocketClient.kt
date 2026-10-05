package com.megablok10.kit.net

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Отправка одной строки по TCP: открыть сокет → записать строку → закрыть. Одно соединение = одно сообщение — для редких
 * сообщений в игровой сети это проще долгоживущих соединений и не требует своего keep-alive. Доставка best-effort: очередь и
 * повторы — забота вызывающего (см. mesh.Outbox).
 *
 * Сокет создаётся обычный: если приложение привязало процесс к Wi-Fi (Android bindProcessToNetwork), трафик пойдёт туда.
 *
 * Строка уходит в UTF-8 с `\n` в конце. Пишем через OutputStreamWriter, а не PrintWriter: удобный конструктор
 * PrintWriter(OutputStream, Boolean, Charset) есть на Android только с API 33 (на Android 8–12 — NoSuchMethodError, это Error,
 * а не Exception, и он ронял приложение при первой же отправке), а сам PrintWriter глотает ошибки записи — из-за этого
 * обрыв уже после соединения выглядел как [SendOutcome.DELIVERED] вместо [SendOutcome.UNKNOWN].
 *
 * Строка в конверте ([LineEnvelope]) с [expectAckFrom]: после записи ждём ответ получателя ([LineAck], не дольше [ackTimeoutMs]):
 * `ok` от ожидаемого ключа — [SendOutcome.DELIVERED] (адресат сохранил строку); `wrong`/`reject` — [SendOutcome.NOT_REACHED]:
 * строку не обработали, можно к следующему адресу; ответа нет, он непонятный или `ok` от чужого ключа — [SendOutcome.UNKNOWN].
 *
 * [onOutcome] узнаёт исход каждой отправки и чей ключ ответил ([answeredBy]) — по нему таблица пиров (mesh.PeerTable.reportSend)
 * ставит рабочий адрес игрока первым, отказавший — в конец, а адрес, где ответил другой игрок, переносит к нему.
 *
 * Соединение, которое не прошло по таймауту, повторяется один раз, но только по адресу, куда недавно ([RETRY_WINDOW_MS]) доходило: телефон
 * с «уснувшим» Wi-Fi отвечает на первый SYN после простоя дольше таймаута (живая проверка 05.10: первое соединение T1→T2 — таймаут 2 с, повтор
 * через 4 с — 350 мс). Повтор безопасен для денег: до записи строки ничего не ушло (NOT_REACHED), а для давно молчащих адресов он не
 * удваивает ожидание.
 */
class LineSocketClient(
    private val log: KitLog = NoopLog,
    private val defaultTimeoutMs: Int = 2000,
    private val ackTimeoutMs: Int = 5000,
    private val socketFactory: () -> Socket = { Socket() },
    private val clock: () -> Long = System::currentTimeMillis,
    // Последним: вызывающие передают его конец-лямбдой.
    private val onOutcome: (host: String, port: Int, outcome: SendOutcome, answeredBy: String?) -> Unit = { _, _, _, _ -> },
) {
    /** Когда по адресу последний раз была доставка (DELIVERED); потоков несколько — отправки идут параллельно. */
    private val lastDelivered = java.util.concurrent.ConcurrentHashMap<String, Long>()

    fun sendLine(host: String, port: Int, line: String, timeoutMs: Int = defaultTimeoutMs): Boolean =
        sendLineOutcome(host, port, line, timeoutMs) == SendOutcome.DELIVERED

    /**
     * Три исхода вместо двух: для денег и предметов важно отличить «не соединились — строка точно не ушла» от «ошибка уже после
     * соединения — получатель мог её получить» (см. handover).
     */
    fun sendLineOutcome(host: String, port: Int, line: String, timeoutMs: Int = defaultTimeoutMs, expectAckFrom: String? = null): SendOutcome {
        var answeredBy: String? = null
        val key = "$host:$port"
        val mayRetryConnect = clock() - (lastDelivered[key] ?: Long.MIN_VALUE / 2) < RETRY_WINDOW_MS
        return connectAndWrite(host, port, line, timeoutMs, expectAckFrom, mayRetryConnect) { answeredBy = it }.also {
            if (it == SendOutcome.DELIVERED) lastDelivered[key] = clock()
            onOutcome(host, port, it, answeredBy)
        }
    }

    private fun connectAndWrite(
        host: String, port: Int, line: String, timeoutMs: Int, expectAckFrom: String?, mayRetryConnect: Boolean, answered: (String) -> Unit,
    ): SendOutcome {
        var socket = socketFactory()
        val started = clock()
        fun took() = clock() - started
        return try {
            try {
                try {
                    socket.connect(InetSocketAddress(host, port), timeoutMs)
                } catch (e: java.net.SocketTimeoutException) {
                    if (!mayRetryConnect) throw e
                    log.warnEvent(TAG, "send.connect_retry", "to" to "$host:$port", "ms" to took())
                    try { socket.close() } catch (ignored: Exception) { /* после неудачного connect сокет негоден */ }
                    socket = socketFactory()
                    socket.connect(InetSocketAddress(host, port), timeoutMs)
                }
            } catch (e: Exception) {
                log.warnEvent(TAG, "send.not_reached", "to" to "$host:$port", "error" to e.javaClass.simpleName, "msg" to e.message, "ms" to took(), "chars" to line.length)
                return SendOutcome.NOT_REACHED
            }
            val writer = OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)
            writer.write(line)
            writer.write("\n")
            writer.flush()
            if (expectAckFrom != null) return awaitAck(socket, host, port, expectAckFrom, answered) { took() }
            log.d(TAG, "send.delivered to=$host:$port ms=${took()} chars=${line.length}")
            SendOutcome.DELIVERED
        } catch (e: Exception) {
            log.warnEvent(TAG, "send.unknown", "to" to "$host:$port", "error" to e.javaClass.simpleName, "msg" to e.message, "ms" to took())
            SendOutcome.UNKNOWN
        } finally {
            try { socket.close() } catch (e: Exception) { /* уже закрыт */ }
        }
    }

    private fun awaitAck(socket: Socket, host: String, port: Int, expected: String, answered: (String) -> Unit, took: () -> Long): SendOutcome {
        socket.soTimeout = ackTimeoutMs
        val raw = try { readBoundedLine(socket.getInputStream(), MAX_ACK_CHARS) } catch (e: java.net.SocketTimeoutException) { null }
        val ack = raw?.let(LineAck::decode)
        if (ack == null) {
            // Записали, а ответа нет: получатель на старой версии, упал или не успел сохранить — могло дойти.
            log.warnEvent(TAG, "send.no_ack", "to" to "$host:$port", "got" to (raw?.take(24) ?: "-"), "ms" to took())
            return SendOutcome.UNKNOWN
        }
        answered(ack.key)
        return when {
            ack.status == LineAck.Status.OK && ack.key == expected -> {
                log.d(TAG, "send.delivered to=$host:$port ms=${took()} ack=ok")
                SendOutcome.DELIVERED
            }
            ack.status == LineAck.Status.OK -> {
                log.warnEvent(TAG, "send.ack_other_key", "to" to "$host:$port", "expected" to expected.take(8), "got" to ack.key.take(8))
                SendOutcome.UNKNOWN
            }
            else -> {
                // wrong — там другой игрок; reject — адресат, но строку не принял. В обоих случаях она не обработана.
                log.warnEvent(TAG, "send.not_accepted", "to" to "$host:$port", "status" to ack.status.wire, "by" to ack.key.take(8), "ms" to took())
                SendOutcome.NOT_REACHED
            }
        }
    }

    private companion object {
        const val TAG = "Socket"
        const val MAX_ACK_CHARS = 1024
        /** Повторять соединение по таймауту только по адресу, куда доходило не раньше, чем столько назад. */
        const val RETRY_WINDOW_MS = 5 * 60_000L
    }
}

enum class SendOutcome {
    /** Соединились и записали строку. */
    DELIVERED,
    /** Соединиться не удалось — строка точно не ушла. */
    NOT_REACHED,
    /** Соединение было, но что-то сломалось при отправке: получатель мог получить строку, мог и нет. */
    UNKNOWN
}
