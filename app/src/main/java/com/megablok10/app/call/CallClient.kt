package com.megablok10.app.call

import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.Socket

/** Тот же принцип, что и ChatClient: одна строка на соединение, доставка best-effort. */
object CallClient {
    fun send(host: String, port: Int, signal: CallSignal, timeoutMs: Int = 2000): Boolean = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), timeoutMs)
            PrintWriter(socket.getOutputStream(), true, Charsets.UTF_8).apply {
                println(CallProtocol.encode(signal))
                flush()
            }
        }
        true
    } catch (e: Exception) {
        false
    }
}
