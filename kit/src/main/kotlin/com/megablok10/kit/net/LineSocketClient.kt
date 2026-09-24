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
 */
class LineSocketClient(private val log: KitLog = NoopLog, private val defaultTimeoutMs: Int = 2000) {
    fun sendLine(host: String, port: Int, line: String, timeoutMs: Int = defaultTimeoutMs): Boolean =
        sendLineOutcome(host, port, line, timeoutMs) == SendOutcome.DELIVERED

    /**
     * Три исхода вместо двух: для денег и предметов важно отличить «не соединились — строка точно не ушла» от «ошибка уже после
     * соединения — получатель мог её получить» (см. handover).
     */
    fun sendLineOutcome(host: String, port: Int, line: String, timeoutMs: Int = defaultTimeoutMs): SendOutcome {
        val socket = Socket()
        val started = System.currentTimeMillis()
        fun took() = System.currentTimeMillis() - started
        return try {
            try {
                socket.connect(InetSocketAddress(host, port), timeoutMs)
            } catch (e: Exception) {
                log.warnEvent(TAG, "send.not_reached", "to" to "$host:$port", "error" to e.javaClass.simpleName, "msg" to e.message, "ms" to took(), "chars" to line.length)
                return SendOutcome.NOT_REACHED
            }
            val writer = OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)
            writer.write(line)
            writer.write("\n")
            writer.flush()
            log.d(TAG, "send.delivered to=$host:$port ms=${took()} chars=${line.length}")
            SendOutcome.DELIVERED
        } catch (e: Exception) {
            log.warnEvent(TAG, "send.unknown", "to" to "$host:$port", "error" to e.javaClass.simpleName, "msg" to e.message, "ms" to took())
            SendOutcome.UNKNOWN
        } finally {
            try { socket.close() } catch (e: Exception) { /* уже закрыт */ }
        }
    }

    private companion object { const val TAG = "Socket" }
}

enum class SendOutcome {
    /** Соединились и записали строку. */
    DELIVERED,
    /** Соединиться не удалось — строка точно не ушла. */
    NOT_REACHED,
    /** Соединение было, но что-то сломалось при отправке: получатель мог получить строку, мог и нет. */
    UNKNOWN
}
