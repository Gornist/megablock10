package com.megablok10.netrun.bridge.phone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Строки запроса входа `MB10ENTER` v1 и v2 (протокол, раздел 8): кодек, байты подписи, отказ на чужую версию. */
class PhoneWireEnterTest {
    private fun request(ram: Int?) =
        EnterRequest("e-7d1c", "t03", "KEY", "Призрак: Ночной", listOf("tr_1", "tr_2"), "tr_1", 1790000499000, "SIG", ram)

    @Test fun v1RoundTripHasTenPartsAndNoRam() {
        val line = PhoneWire.encodeEnter(request(null))
        assertTrue(line, line.startsWith("MB10ENTER:v1:e-7d1c:t03:KEY:"))
        assertEquals(10, line.split(":").size)
        assertEquals(request(null), PhoneWire.decodeEnter(line))
    }

    @Test fun v2RoundTripCarriesRamBeforeTimestamp() {
        val line = PhoneWire.encodeEnter(request(8))
        assertTrue(line, line.startsWith("MB10ENTER:v2:e-7d1c:t03:KEY:"))
        val parts = line.split(":")
        assertEquals(11, parts.size)
        assertEquals("tr_1,tr_2", parts[6])
        assertEquals("tr_1", parts[7])
        assertEquals("8", parts[8])
        assertEquals("1790000499000", parts[9])
        assertEquals(request(8), PhoneWire.decodeEnter(line))
    }

    @Test fun signedBytesDifferForV1AndV2() {
        assertEquals("ENTER1|e-7d1c|t03|KEY|Призрак: Ночной|tr_1,tr_2|tr_1|1790000499000", String(PhoneWire.enterSignedBytes(request(null)), Charsets.UTF_8))
        assertEquals("ENTER2|e-7d1c|t03|KEY|Призрак: Ночной|tr_1,tr_2|tr_1|8|1790000499000", String(PhoneWire.enterSignedBytes(request(8)), Charsets.UTF_8))
    }

    @Test fun malformedLinesAreRejected() {
        assertNull("v2 с десятью частями", PhoneWire.decodeEnter("MB10ENTER:v2:a:b:c:d:e:f:1:s"))
        assertNull("ram не число", PhoneWire.decodeEnter("MB10ENTER:v2:a:b:c:d:e:f:x:1:s"))
        assertNull("v3", PhoneWire.decodeEnter("MB10ENTER:v3:a:b:c:d:e:f:6:1:s"))
        assertNull("ts не число", PhoneWire.decodeEnter("MB10ENTER:v2:a:b:c:d:e:f:6:x:s"))
    }
}
