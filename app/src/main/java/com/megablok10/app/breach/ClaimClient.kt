package com.megablok10.app.breach

import com.megablok10.app.data.SlotClaimEntity
import com.megablok10.app.net.LineTransport

/** Тот же принцип, что у ChatClient/CallClient: одна строка на соединение, доставка best-effort. */
object ClaimClient {
    fun send(host: String, port: Int, claim: SlotClaimEntity, timeoutMs: Int = 2000): Boolean =
        LineTransport.client.sendLine(host, port, ClaimProtocol.encode(claim), timeoutMs)
}
