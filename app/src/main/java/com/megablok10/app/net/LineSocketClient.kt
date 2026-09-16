package com.megablok10.app.net

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
    fun sendLine(host: String, port: Int, line: String, timeoutMs: Int = 2000): Boolean = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), timeoutMs)
            PrintWriter(socket.getOutputStream(), true, Charsets.UTF_8).apply {
                println(line)
                flush()
            }
        }
        true
    } catch (e: Exception) {
        false
    }
}
