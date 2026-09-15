package com.megablok10.app.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Как и у Mb10QrCodec, риск здесь — свободный текст (позывной, фракция,
 * текст сообщения) внутри двоеточие-разделённой строки; эти тесты специально
 * гоняют текст с двоеточиями/кириллицей/пунктуацией через полный цикл.
 */
class ChatProtocolTest {

    @Test
    fun `faction message round-trips`() {
        val msg = ChatWireMessage(
            type = ChatMessageType.FACTION,
            fromPubKeyB64 = "pubKeyB64==",
            fromCallsign = "Zipa_09",
            fromFaction = "Отряд: самообороны",
            toPubKeyB64 = "",
            timestamp = 1234567890L,
            body = "Всем оставаться на 8 этаже. К клинике: не подходить."
        )
        val decoded = ChatProtocol.decode(ChatProtocol.encode(msg))
        assertEquals(msg, decoded)
    }

    @Test
    fun `dm round-trips with colons and cyrillic in the body`() {
        val msg = ChatWireMessage(
            type = ChatMessageType.DM,
            fromPubKeyB64 = "pubKeyB64==",
            fromCallsign = "Ольга",
            fromFaction = "Клемты",
            toPubKeyB64 = "otherPubKeyB64==",
            timestamp = 42L,
            body = "Встречаемся у техэтажа: 21:40, не опаздывай."
        )
        val decoded = ChatProtocol.decode(ChatProtocol.encode(msg))
        assertEquals(msg, decoded)
    }

    @Test
    fun `unknown magic prefix decodes to null`() {
        assertNull(ChatProtocol.decode("NOTMB10CHAT:v1:FACTION:a:b:c:d:1:e"))
    }

    @Test
    fun `truncated message decodes to null instead of throwing`() {
        assertNull(ChatProtocol.decode("MB10CHAT:v1:FACTION:only-a-few-parts"))
    }

    @Test
    fun `unknown message type decodes to null instead of throwing`() {
        assertNull(ChatProtocol.decode("MB10CHAT:v1:UNKNOWN:pub==:Y3M=:ZmFj:::1:Ym9keQ=="))
    }

    @Test
    fun `non-numeric timestamp decodes to null instead of throwing`() {
        assertNull(ChatProtocol.decode("MB10CHAT:v1:FACTION:pub==:Y3M=:ZmFj::notanumber:Ym9keQ=="))
    }

    @Test
    fun `garbage base64 in a free-text field decodes to null instead of throwing`() {
        assertNull(ChatProtocol.decode("MB10CHAT:v1:FACTION:pub==:not-valid-base64!!!:ZmFj::1:Ym9keQ=="))
    }
}
