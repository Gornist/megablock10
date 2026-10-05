package com.megablok10.app.headset

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/** Адрес очков: токен в query, порт по умолчанию 7420, мусор отвергается; в журнал годится только host:port. */
class HeadsetConfigTest {
    private fun cfg(address: String, token: String = "tok-1_A") = HeadsetConfig(enabled = true, address = address, token = token)

    @Test fun defaultsAreOff() {
        val c = HeadsetConfig()
        assertFalse(c.enabled)
        assertNull(c.url())
    }

    @Test fun hostWithoutPortUsesDefaultPort() = assertEquals("ws://192.168.1.50:7420/?token=tok-1_A", cfg("192.168.1.50").url())

    @Test fun explicitPortAndSurroundingSpacesAreAccepted() = assertEquals("ws://pico.local:7500/?token=tok-1_A", cfg("  pico.local:7500 ").url())

    @Test fun badAddressesAreRejected() {
        for (bad in listOf("", "http://1.2.3.4", "1.2.3.4:", "1.2.3.4:0", "1.2.3.4:70000", "ho st", "1.2.3.4/path", "a:b")) {
            assertNull("«$bad» не должен годиться", cfg(bad).url())
        }
    }

    @Test fun badTokensAreRejectedSoNothingNeedsEncoding() {
        for (bad in listOf("", "a b", "a&b=c", "токен", "a/b", "a?b")) {
            assertNull("токен «$bad» не должен годиться", cfg("1.2.3.4", bad).url())
        }
    }

    @Test fun logLineNeverContainsTheToken() {
        val c = cfg("192.168.1.50:7420", "secret-token")
        assertEquals("192.168.1.50:7420", c.hostPort())
        assertFalse(c.hostPort().contains("secret"))
        assertEquals("192.168.1.50:7420", cfg("192.168.1.50").hostPort())
    }
}
