package com.megablok10.app.netrun

import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.crypto.Ecdsa
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Строки входа в «Сеть» — близнец PhoneWire Моста (netrun-bridge). Примеры строк ниже сняты с формата из протокола, раздел 8: если
 * тест краснеет — разошёлся формат с Мостом, а не просто «поправился тест».
 */
class NetrunWireTest {
    private val runner = TestPlayer("Призрак")
    private val world = TestPlayer("Мост")

    private fun request(): EnterRequest {
        val r = EnterRequest("e-7d1c", "t03", runner.key, "Призрак: Ночной", listOf("tr_88e1", "tr_88e2"), "tr_88e1", 1790000499000)
        return r.copy(signature = runner.sign(NetrunWire.enterSignedBytes(r)))
    }

    @Test fun `enter request round-trips and its signature verifies with the runner key`() {
        val r = request()
        val back = NetrunWire.decodeEnter(NetrunWire.encodeEnter(r))!!
        assertEquals(r, back)
        assertTrue(Ecdsa.verify(runner.key, NetrunWire.enterSignedBytes(back), back.signature))
    }

    @Test fun `enter wire layout is the bridge format`() {
        val r = EnterRequest("e-1", "t03", "KEY", "Ник", listOf("a", "b"), "a", 5, "SIG")
        assertEquals("MB10ENTER:v1:e-1:t03:KEY:${com.megablok10.kit.text.Base64Text.encode("Ник")}:a,b:a:5:SIG", NetrunWire.encodeEnter(r))
        assertEquals("ENTER1|e-1|t03|KEY|Ник|a,b|a|5", String(NetrunWire.enterSignedBytes(r), Charsets.UTF_8))
    }

    @Test fun `entered reply round-trips and verifies only with the world key`() {
        val unsigned = EnterReply("e-7d1c", false, "", "session_state", "терминал: занят", "")
        val reply = unsigned.copy(signature = world.sign(NetrunWire.enteredSignedBytes(unsigned)))
        val back = NetrunWire.decodeEntered(NetrunWire.encodeEntered(reply))!!
        assertEquals(reply, back)
        assertTrue(Ecdsa.verify(world.key, NetrunWire.enteredSignedBytes(back), back.signature))
        assertFalse(Ecdsa.verify(runner.key, NetrunWire.enteredSignedBytes(back), back.signature))
    }

    @Test fun `entered wire layout is the bridge format`() {
        val r = EnterReply("e-1", true, "s_9f", "", "", "SIG")
        val b = com.megablok10.kit.text.Base64Text.encode("s_9f")
        assertEquals("MB10ENTERED:v1:e-1:1:$b:::SIG", NetrunWire.encodeEntered(r))
        assertEquals("ENTERED1|e-1|1|s_9f||", String(NetrunWire.enteredSignedBytes(r), Charsets.UTF_8))
    }

    @Test fun `other versions and shapes are not recognised`() {
        assertNull(NetrunWire.decodeEntered("MB10ENTERED:v2:e-1:1:::SIG"))
        assertNull(NetrunWire.decodeEntered("MB10ENTERED:v1:e-1:1"))
        assertNull(NetrunWire.decodeEnter("MB10ENTER:v2:a:b:c:d:e:f:1:s"))
        assertNull("ENTERED не принимается за ENTER", NetrunWire.decodeEnter(NetrunWire.encodeEntered(EnterReply("e", true, "s", "", "", "S"))))
        assertNull(NetrunWire.decodeEntered("MB10CHAT:v1:DM:a:b:c:d:1:e"))
    }
}
