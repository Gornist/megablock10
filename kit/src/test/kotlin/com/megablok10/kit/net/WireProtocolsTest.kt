package com.megablok10.kit.net

import com.megablok10.kit.time.ManualClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WireProtocolsTest {
    private val protocols = WireProtocols(mapOf("CHAT" to 1, "CALL" to 2))

    @Test fun parseReadsOnlyVPrefixedNumbers() {
        assertEquals(2, WireProtocols.parseVersion("v2"))
        assertEquals(12, WireProtocols.parseVersion("v12"))
        assertNull(WireProtocols.parseVersion("2"))
        assertNull(WireProtocols.parseVersion("vx"))
        assertNull(WireProtocols.parseVersion("v"))
        assertNull(WireProtocols.parseVersion(""))
    }

    @Test fun matchesOnlyOwnMagicAndVersion() {
        assertTrue(protocols.matches("CHAT:v1:x".split(":"), "CHAT"))
        assertFalse(protocols.matches("CHAT:v2:x".split(":"), "CHAT"))
        assertFalse(protocols.matches("CALL:v2:x".split(":"), "CHAT"))
        assertFalse(protocols.matches(listOf("CHAT"), "CHAT"))
        assertFalse(protocols.matches("OTHER:v1".split(":"), "OTHER"))
    }

    @Test fun mismatchOnlyForKnownProtocolOfOtherVersion() {
        assertEquals("CHAT" to 2, protocols.mismatch("CHAT:v2:x"))
        assertEquals("CALL" to null, protocols.mismatch("CALL:zzz:x"))
        assertNull(protocols.mismatch("CHAT:v1:x"))
        assertNull(protocols.mismatch("GET / HTTP/1.1"))
        assertNull(protocols.mismatch(""))
    }

    @Test fun reporterNotifiesOncePerCooldownPerVersionPair() {
        val clock = ManualClock(1_000L)
        val shown = mutableListOf<String>()
        val r = IncompatibleVersionReporter(protocols, "обновите приложение", clock) { shown += it }
        r.report("CHAT:v0:x"); r.report("CHAT:v0:x")
        assertEquals(listOf("обновите приложение"), shown)
        clock.advance(IncompatibleVersionReporter.COOLDOWN_MS - 1)
        r.report("CHAT:v0:x")
        assertEquals(1, shown.size)
        clock.advance(2)
        r.report("CHAT:v0:x")
        assertEquals(2, shown.size)
        r.report("CALL:v1:x") // другая пара — отдельное уведомление
        assertEquals(3, shown.size)
    }

    @Test fun reporterIgnoresCompatibleAndForeignLines() {
        val shown = mutableListOf<String>()
        val r = IncompatibleVersionReporter(protocols, "x", ManualClock()) { shown += it }
        r.report("CHAT:v1:x"); r.report("junk"); r.report("")
        assertTrue(shown.isEmpty())
    }
}
