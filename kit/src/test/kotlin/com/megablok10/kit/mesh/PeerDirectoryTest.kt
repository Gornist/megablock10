package com.megablok10.kit.mesh

import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Одно место адресации (B1): вызывающий знает только ключ игрока, адрес выбирает таблица, перебор — справочник. */
class PeerDirectoryTest {
    private fun peer(id: String, port: Int, host: String = "10.10.0.$id", faction: String = "F") = PeerInfo(id, "cs$id", faction, host, port)

    private class Wire(val outcomes: Map<Int, SendOutcome>) {
        val tried = mutableListOf<Int>()
        fun send(port: Int): SendOutcome { tried += port; return outcomes[port] ?: SendOutcome.DELIVERED }
    }

    private val lines = mutableListOf<String>()

    private fun directory(t: PeerTable, wire: Wire) = PeerDirectory({ t.peers.value }, t.players, me = { "me" to 47100 }) { h, p, l, expect ->
        lines += "$expect|$l"
        wire.send(p).also { t.reportSend(h, p, it) } // как LineSocketClient(onOutcome) в приложении
    }

    @Test fun everyLineGoesInAnEnvelopeToTheExpectedPlayer() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1", 4000))
        directory(t, Wire(emptyMap())).send("1", "MB10CHAT:v1:x")
        assertEquals(listOf("1|MB10TO:v1:1:me:47100:MB10CHAT:v1:x"), lines)
    }

    @Test fun sendGoesPastTheDeadAddressAndRemembersTheLiveOne() = runTest {
        val t = PeerTable { this }
        t.found("mb10-a", peer("1", 4000))
        t.found("mb10-a", peer("1", 4001)) // перезапуск — и тут же устаревший ответ кэша mDNS
        t.found("mb10-a", peer("1", 4000))
        val wire = Wire(mapOf(4001 to SendOutcome.NOT_REACHED))
        val dir = directory(t, wire)
        assertEquals(SendOutcome.DELIVERED, dir.send("1", "x"))
        assertEquals(listOf(4001, 4000), wire.tried)
        wire.tried.clear()
        dir.send("1", "y")
        assertEquals("мёртвый адрес больше не первым", listOf(4000), wire.tried)
    }

    @Test fun unknownIsNotRepeatedOnAnotherAddress() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1", 4000))
        t.addStatic(peer("1", 5000, host = "10.0.2.2"))
        val wire = Wire(mapOf(4000 to SendOutcome.UNKNOWN, 5000 to SendOutcome.UNKNOWN))
        assertEquals(SendOutcome.UNKNOWN, directory(t, wire).send("1", "деньги"))
        assertEquals(1, wire.tried.size)
    }

    @Test fun invisiblePlayerIsNotReachedWithoutTouchingTheWire() = runTest {
        val wire = Wire(emptyMap())
        val dir = directory(PeerTable { this }, wire)
        assertEquals(SendOutcome.NOT_REACHED, dir.send("nobody", "x"))
        assertTrue(wire.tried.isEmpty())
        assertFalse(dir.isOnline("nobody"))
    }

    @Test fun onlineHasOnePlayerPerKeyAndSendToAllSendsOncePerPlayer() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1", 4000))
        t.addStatic(peer("1", 5000, host = "10.0.2.2"))
        t.found("b", peer("2", 4000, faction = "G"))
        val wire = Wire(emptyMap())
        val dir = directory(t, wire)
        assertEquals(listOf(OnlinePlayer("1", "cs1", "F"), OnlinePlayer("2", "cs2", "G")), dir.online.value)
        assertEquals(mapOf("1" to SendOutcome.DELIVERED), dir.sendToAll("x") { it.faction == "F" })
        assertEquals(1, wire.tried.size)
        assertEquals(2, dir.sendToAll("y").size)
    }
}
