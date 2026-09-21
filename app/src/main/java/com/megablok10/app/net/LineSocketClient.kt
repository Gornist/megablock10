package com.megablok10.app.net

import com.megablok10.app.log.Mb10Log
import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Общая механика для ChatClient/CallClient: открыть сокет → отправить одну
 * строку → закрыть. Доставка best-effort — если получатель offline, просто
 * не достучаться, очереди/ретраев нет. Оба клиента отличались только тем,
 * какой Protocol.encode() вызывали, поэтому сама отправка строки вынесена
 * сюда одним местом.
 */
object LineSocketClient {
    fun sendLine(host: String, port: Int, line: String, timeoutMs: Int = 2000): Boolean =
        sendLineOutcome(host, port, line, timeoutMs) == SendOutcome.DELIVERED

    /**
     * Три исхода вместо двух: для денег и предметов важно отличить «не соединились — строка точно не ушла» от «ошибка уже после соединения —
     * получатель мог её получить» (см. TransactionStore.deliverOutgoing).
     */
    fun sendLineOutcome(host: String, port: Int, line: String, timeoutMs: Int = 2000): SendOutcome {
        val socket = Socket()
        val started = System.currentTimeMillis()
        fun took() = System.currentTimeMillis() - started
        return try {
            try {
                socket.connect(InetSocketAddress(host, port), timeoutMs)
            } catch (e: Exception) {
                Mb10Log.warnEvent("Socket", "send.not_reached", "to" to "$host:$port", "error" to e.javaClass.simpleName, "msg" to e.message, "ms" to took(), "chars" to line.length)
                return SendOutcome.NOT_REACHED
            }
            PrintWriter(socket.getOutputStream(), true, Charsets.UTF_8).apply {
                println(line)
                flush()
            }
            Mb10Log.d("Socket", "send.delivered to=$host:$port ms=${took()} chars=${line.length}")
            SendOutcome.DELIVERED
        } catch (e: Exception) {
            Mb10Log.warnEvent("Socket", "send.unknown", "to" to "$host:$port", "error" to e.javaClass.simpleName, "msg" to e.message, "ms" to took())
            SendOutcome.UNKNOWN
        } finally {
            try { socket.close() } catch (e: Exception) { /* уже закрыт */ }
        }
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
