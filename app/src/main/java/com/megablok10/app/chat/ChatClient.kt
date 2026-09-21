package com.megablok10.app.chat

import com.megablok10.app.net.LineSocketClient
import com.megablok10.app.net.SendOutcome

/** Доставка best-effort: если получатель offline, просто не достучаться — очереди/ретраев нет. */
object ChatClient {
    fun send(host: String, port: Int, message: ChatWireMessage, timeoutMs: Int = 2000): Boolean =
        sendOutcome(host, port, message, timeoutMs) == SendOutcome.DELIVERED

    fun sendOutcome(host: String, port: Int, message: ChatWireMessage, timeoutMs: Int = 2000): SendOutcome =
        LineSocketClient.sendLineOutcome(host, port, ChatProtocol.encode(message), timeoutMs)
}
