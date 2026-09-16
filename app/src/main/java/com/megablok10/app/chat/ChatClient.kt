package com.megablok10.app.chat

import com.megablok10.app.net.LineSocketClient

/** Доставка best-effort: если получатель offline, просто не достучаться — очереди/ретраев нет. */
object ChatClient {
    fun send(host: String, port: Int, message: ChatWireMessage, timeoutMs: Int = 2000): Boolean =
        LineSocketClient.sendLine(host, port, ChatProtocol.encode(message), timeoutMs)
}
