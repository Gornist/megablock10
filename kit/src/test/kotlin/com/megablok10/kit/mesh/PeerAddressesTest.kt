package com.megablok10.kit.mesh

import com.megablok10.kit.net.SendOutcome
import org.junit.Assert.assertEquals
import org.junit.Test

/** Несколько адресов одного игрока (NSD с портом прошлого процесса, статический, подсказка сервера): отправка не застревает на устаревшем. */
class PeerAddressesTest {
    private val staleNsd = PeerInfo("alice", "Alice", "Neon", "10.0.2.16", 37157)
    private val static = PeerInfo("alice", "Alice", "Neon", "10.0.2.2", 21277)
    private val bob = PeerInfo("bob", "Bob", "Rats", "10.0.2.17", 36675)

    @Test fun addressesOfKeepsTableOrderAndSkipsOthersAndDuplicates() {
        val peers = listOf(staleNsd, bob, static, staleNsd.copy(callsign = "Alice (дубль)"))
        assertEquals(listOf(staleNsd, static), peers.addressesOf("alice"))
        assertEquals(emptyList<PeerInfo>(), peers.addressesOf("carol"))
    }

    @Test fun bestPerPlayerKeepsTheFirstAddressOfEachPlayer() {
        val best = listOf(static, staleNsd, bob).bestPerPlayer()
        assertEquals(listOf("alice", "bob"), best.keys.toList())
        assertEquals(static, best["alice"])
    }

    @Test fun notReachedMovesOnToTheNextAddress() {
        val tried = mutableListOf<PeerInfo>()
        val outcome = sendToFirstReachable(listOf(staleNsd, static)) { tried += it; if (it == staleNsd) SendOutcome.NOT_REACHED else SendOutcome.DELIVERED }
        assertEquals(SendOutcome.DELIVERED, outcome)
        assertEquals(listOf(staleNsd, static), tried)
    }

    @Test fun unknownStopsBecauseTheLineMayHaveArrived() {
        val tried = mutableListOf<PeerInfo>()
        val outcome = sendToFirstReachable(listOf(staleNsd, static)) { tried += it; SendOutcome.UNKNOWN }
        assertEquals(SendOutcome.UNKNOWN, outcome)
        assertEquals("по второму адресу не повторяем", listOf(staleNsd), tried)
    }

    @Test fun noAddressesOrNoneReachableIsNotReached() {
        assertEquals(SendOutcome.NOT_REACHED, sendToFirstReachable(emptyList()) { error("не должен звать") })
        assertEquals(SendOutcome.NOT_REACHED, sendToFirstReachable(listOf(staleNsd, static)) { SendOutcome.NOT_REACHED })
    }
}
