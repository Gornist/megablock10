package com.megablok10.app.net

import com.megablok10.app.breach.ClaimProtocol
import com.megablok10.app.call.CallProtocol
import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatProtocol
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.kit.net.IncompatibleVersionReporter
import com.megablok10.kit.net.LineEnvelope
import com.megablok10.kit.time.ManualClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WireVersionTest {
    private val msg = ChatWireMessage(ChatMessageType.DM, "pk==", "Ольга", "Клемты", "to==", 42L, "привет: мир")
    private val line = ChatProtocol.encode(msg)

    /** Короткое имя из `wireVersions` дашборда → магия протокола в [WireVersion.SUPPORTED]. */
    private val magicOfReported = mapOf("chat" to "MB10CHAT", "call" to "MB10CALL", "claim" to "MB10CLAIM", "read" to "MB10READ", "to" to LineEnvelope.MAGIC)

    @Test fun reportedVersionsMatchSupportedOnes() {
        assertEquals(mapOf("chat" to WireVersion.CHAT, "call" to WireVersion.CALL, "claim" to WireVersion.CLAIM, "read" to WireVersion.READ, "to" to WireVersion.ENVELOPE), WireVersion.REPORTED)
        // по ключам, а не по множествам значений: новый протокол с версией 1 «растворился» бы среди одинаковых единиц
        assertEquals(magicOfReported.keys, WireVersion.REPORTED.keys)
        for ((short, magic) in magicOfReported) {
            assertEquals("версия «$short» в REPORTED и $magic в SUPPORTED", WireVersion.SUPPORTED[magic], WireVersion.REPORTED[short])
        }
    }

    /**
     * Протоколы, которые приложение понимает, но дашборду не сообщает (голос и вход в Сеть, аудит 17.10). Добавление в REPORTED —
     * контракт с Коллектором (`wireVersions` в presence): сервер сначала принимает ключи. Новый протокол в SUPPORTED без записи
     * сюда и без короткого имени в REPORTED этот тест красит — решение «сообщать или нет» принимается явно.
     */
    @Test fun everySupportedProtocolIsEitherReportedOrListedAsKnownGap() {
        val knownGap = setOf("MB10VOICE", "MB10LISTEN", "MB10ENTER", "MB10ENTERED")
        assertEquals(knownGap, WireVersion.SUPPORTED.keys - magicOfReported.values.toSet())
    }

    @Test fun ownVersionRoundTrips() {
        assertTrue(line.startsWith("MB10CHAT:v${WireVersion.CHAT}:"))
        assertEquals(msg, ChatProtocol.decode(line))
    }

    @Test fun otherChatVersionIsRejectedNotMisparsed() {
        val future = line.replaceFirst(":v${WireVersion.CHAT}:", ":v${WireVersion.CHAT + 1}:")
        assertNull(ChatProtocol.decode(future))
        assertEquals("MB10CHAT" to WireVersion.CHAT + 1, WireVersion.mismatch(future))
    }

    @Test fun oldCallAndClaimVersionsAreRejected() {
        assertNull(CallProtocol.decode("MB10CALL:v1:OFFER:c:pk:cs:to:1:::-1:"))
        assertNull(ClaimProtocol.decode("MB10CLAIM:v9:slot:key:1:sig"))
        assertEquals("MB10CALL" to 1, WireVersion.mismatch("MB10CALL:v1:OFFER:c:pk:cs:to:1:::-1:"))
    }

    @Test fun matchingOrUnrelatedLinesAreNotMismatches() {
        assertNull(WireVersion.mismatch(line))
        assertNull(WireVersion.mismatch("GET / HTTP/1.1"))
        assertNull(WireVersion.mismatch("MB10:TX:v2:x"))
        assertNull(WireVersion.mismatch(""))
    }

    @Test fun garbledVersionOfKnownProtocolIsMismatchWithUnknownVersion() {
        assertEquals("MB10CHAT" to null, WireVersion.mismatch("MB10CHAT:zzz:DM:a"))
    }

    @Test fun reporterUsesGameProtocolsAndPlayerMessage() {
        val shown = mutableListOf<String>()
        val r = IncompatibleVersionReporter(WireVersion.protocols, WireVersion.INCOMPATIBLE_MESSAGE, ManualClock()) { shown += it }
        r.report(line)
        r.report("MB10CHAT:v0:DM:x")
        assertEquals(listOf(WireVersion.INCOMPATIBLE_MESSAGE), shown)
    }
}
