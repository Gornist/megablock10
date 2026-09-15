package com.megablok10.app.chat

import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.Socket

/** Открыть сокет → отправить одну строку → закрыть. Доставка best-effort: если получатель offline, просто не достучаться — очереди/ретраев нет. */
object ChatClient {
    fun send(host: String, port: Int, message: ChatWireMessage, timeoutMs: Int = 2000): Boolean = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), timeoutMs)
            PrintWriter(socket.getOutputStream(), true, Charsets.UTF_8).apply {
                println(ChatProtocol.encode(message))
                flush()
            }
        }
        true
    } catch (e: Exception) {
        false
    }
}
