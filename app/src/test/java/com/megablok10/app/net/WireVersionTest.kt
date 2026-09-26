package com.megablok10.app.net

import com.megablok10.app.breach.ClaimProtocol
import com.megablok10.app.call.CallProtocol
import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatProtocol
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.kit.net.IncompatibleVersionReporter
import com.megablok10.kit.time.ManualClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WireVersionTest {
    private val msg = ChatWireMessage(ChatMessageType.DM, "pk==", "Ольга", "Клемты", "to==", 42L, "привет: мир")
    private val line = ChatProtocol.encode(msg)

    @Test fun reportedVersionsMatchSupportedOnes() {
        assertEquals(mapOf("chat" to WireVersion.CHAT, "call" to WireVersion.CALL, "claim" to WireVersion.CLAIM, "read" to WireVersion.READ, "to" to WireVersion.ENVELOPE), WireVersion.REPORTED)
        assertEquals(WireVersion.SUPPORTED.values.toSet(), WireVersion.REPORTED.values.toSet())
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
