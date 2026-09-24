package com.megablok10.app.call

import com.megablok10.app.net.LineTransport

/** Тот же принцип, что и ChatClient: одна строка на соединение, доставка best-effort. */
object CallClient {
    fun send(host: String, port: Int, signal: CallSignal, timeoutMs: Int = 2000): Boolean =
        LineTransport.client.sendLine(host, port, CallProtocol.encode(signal), timeoutMs)
}
