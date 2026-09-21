package com.megablok10.app.net

import com.megablok10.app.breach.ClaimProtocol
import com.megablok10.app.call.CallProtocol
import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatProtocol
import com.megablok10.app.chat.ChatWireMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WireVersionTest {
    private val msg = ChatWireMessage(ChatMessageType.DM, "pk==", "Ольга", "Клемты", "to==", 42L, "привет: мир")
    private val line = ChatProtocol.encode(msg)

    @Test fun parseReadsOnlyVPrefixedNumbers() {
        assertEquals(2, WireVersion.parse("v2"))
        assertEquals(12, WireVersion.parse("v12"))
        assertNull(WireVersion.parse("2"))
        assertNull(WireVersion.parse("vx"))
        assertNull(WireVersion.parse("v"))
        assertNull(WireVersion.parse(""))
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

    @Test fun reporterNotifiesOncePerMinutePerVersionPair() {
        var now = 1_000L
        val shown = mutableListOf<String>()
        val r = IncompatibleVersionReporter({ now }) { shown += it }
        val old = "MB10CHAT:v0:DM:x"
        r.report(old); r.report(old)
        assertEquals(1, shown.size)
        now += IncompatibleVersionReporter.COOLDOWN_MS - 1
        r.report(old)
        assertEquals(1, shown.size)
        now += 2
        r.report(old)
        assertEquals(2, shown.size)
        r.report("MB10CALL:v1:x") // другая пара — отдельное уведомление
        assertEquals(3, shown.size)
    }

    @Test fun reporterIgnoresCompatibleAndForeignLines() {
        val shown = mutableListOf<String>()
        val r = IncompatibleVersionReporter({ 0L }) { shown += it }
        r.report(line); r.report("junk"); r.report("")
        assertTrue(shown.isEmpty())
        assertNotNull(line)
    }
}
