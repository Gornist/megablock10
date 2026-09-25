package com.megablok10.kit.mesh

import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Поведение списка пиров при роуминге и обрывах (docs/network-spec.md, §7) — на виртуальном времени, без устройств. */
@OptIn(ExperimentalCoroutinesApi::class)
class PeerTableTest {
    private fun peer(id: String, host: String = "10.10.0.$id", port: Int = 4000) = PeerInfo(id, "cs$id", "F", host, port)
    private fun keys(t: PeerTable) = t.peers.value.map { it.pubKeyB64 }.sorted()

    @Test fun shortLossDoesNotRemovePeer() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1"))
        t.lost("a")
        advanceTimeBy(LOST_DEBOUNCE_MS - 1)
        assertEquals(listOf("1"), keys(t))
        t.clear()
    }

    @Test fun lossLongerThanDebounceRemovesPeer() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1"))
        t.lost("a")
        advanceTimeBy(LOST_DEBOUNCE_MS + 1)
        assertTrue(keys(t).isEmpty())
    }

    @Test fun foundAgainWithinDebounceKeepsPeer() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1"))
        t.lost("a")
        advanceTimeBy(5_000)
        t.found("a", peer("1", host = "10.10.0.99")) // после роуминга адрес мог смениться
        advanceTimeBy(LOST_DEBOUNCE_MS * 2)
        assertEquals(listOf("10.10.0.99", "10.10.0.1"), t.peers.value.map { it.host }) // новый адрес первым, прежний — запасным
    }

    @Test fun repeatedLostRestartsTheTimer() = runTest {
        val t = PeerTable { this }
        t.found("a", peer("1"))
        t.lost("a")
        advanceTimeBy(8_000)
        t.lost("a")
        advanceTimeBy(8_000) // с первого lost прошло 16 с, со второго — только 8
        assertEquals(listOf("1"), keys(t))
        advanceTimeBy(5_000)
        assertTrue(keys(t).isEmpty())
    }

    @Test fun refreshGraceKeepsNsdPeersUntilDeadlineButNotStaticOrServer() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1"))
        t.addStatic(peer("2"))
        t.updateServerPeers(listOf(peer("3")), "me")
        t.graceAll()
        advanceTimeBy(REFRESH_GRACE_MS - 1)
        assertEquals(listOf("1", "2", "3"), keys(t))
        advanceTimeBy(2)
        assertEquals(listOf("2", "3"), keys(t))
    }

    @Test fun refreshGraceIsCancelledWhenPeerIsRediscovered() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1"))
        t.graceAll()
        advanceTimeBy(3_000)
        t.found("nsd", peer("1"))
        advanceTimeBy(REFRESH_GRACE_MS * 2)
        assertEquals(listOf("1"), keys(t))
    }

    @Test fun snapshotAndRestoreSurviveClear() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1"))
        t.addStatic(peer("2"))
        val saved = t.snapshot()
        t.clear()
        assertTrue(keys(t).isEmpty())
        t.restore(saved)
        assertEquals(listOf("1", "2"), keys(t))
        t.clear()
    }

    @Test fun serverHintIsKeptAsAnotherAddressOfTheSamePlayer() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1"))
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1"), peer("2"), peer("me")), "me")
        assertEquals(listOf("1", "1", "2"), keys(t))
        assertEquals("подсказка свежее записи NSD", listOf("10.10.1.1", "10.10.0.1"), t.peers.value.addressesOf("1").map { it.host })
    }

    @Test fun serverPeerDisappearsWhenServerNoLongerListsIt() = runTest {
        val t = PeerTable { this }
        t.updateServerPeers(listOf(peer("2"), peer("3")), "me")
        t.updateServerPeers(listOf(peer("3")), "me")
        assertEquals(listOf("3"), keys(t))
    }

    @Test fun serverPeersWithBadAddressAreIgnored() = runTest {
        val t = PeerTable { this }
        t.updateServerPeers(listOf(peer("2", port = 0), peer("3", host = " ")), "me")
        assertTrue(keys(t).isEmpty())
    }

    @Test fun sameHintAgainDoesNotJumpAheadOfNsd() = runTest {
        val t = PeerTable { this }
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1")), "me")
        t.found("nsd", peer("1"))
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1")), "me") // heartbeat раз в 30 с — тот же адрес
        assertEquals(listOf("10.10.0.1", "10.10.1.1"), t.peers.value.addressesOf("1").map { it.host })
    }

    // B2 (docs/refactor-plan.md): имя сервиса NSD у игрока одно во всех процессах — после перезапуска меняется только порт.
    private fun firstTried(t: PeerTable, key: String): PeerInfo {
        val tried = mutableListOf<PeerInfo>()
        sendToFirstReachable(t.peers.value.addressesOf(key)) { tried += it; SendOutcome.DELIVERED }
        return tried.single()
    }

    @Test fun playerRestartedWithNewPortFirstSendGoesToTheNewPort() = runTest {
        val t = PeerTable { this }
        t.found("mb10-a", peer("1", port = 33617))
        t.reportSend("10.10.0.1", 33617, SendOutcome.DELIVERED) // до перезапуска всё ходило
        t.found("mb10-a", peer("1", port = 41531))              // перезапуск: новый процесс, новый порт
        assertEquals(41531, firstTried(t, "1").port)
    }

    @Test fun staleNsdAnswerAfterRestartDoesNotHideTheNewPort() = runTest {
        val t = PeerTable { this }
        t.found("mb10-a", peer("1", port = 33617))
        t.found("mb10-a", peer("1", port = 41531))
        t.found("mb10-a", peer("1", port = 33617)) // кэш mDNS снова отдал порт прошлого процесса
        assertEquals(41531, firstTried(t, "1").port)
        assertEquals(listOf(41531, 33617), t.peers.value.addressesOf("1").map { it.port })
    }

    @Test fun nsdRemembersOnlyTheLastFewAddresses() = runTest {
        val t = PeerTable { this }
        (1..NSD_ADDRESS_HISTORY + 2).forEach { t.found("mb10-a", peer("1", port = 4000 + it)) }
        assertEquals(NSD_ADDRESS_HISTORY, t.peers.value.size)
        assertEquals(4000 + NSD_ADDRESS_HISTORY + 2, t.peers.value.first().port)
    }

    @Test fun loopbackHintTakesPortFromServerAndHostFromNsd() = runTest {
        // e2e A4, run 36179242929: сервер видит эмулятор как 127.0.0.1 — верный порт нового процесса, но бесполезный host.
        val t = PeerTable { this }
        t.found("mb10-a", peer("1", host = "10.0.2.16", port = 33617))
        t.updateServerPeers(listOf(peer("1", host = "127.0.0.1", port = 41531)), "me")
        t.found("mb10-a", peer("1", host = "10.0.2.16", port = 33617)) // устаревший ответ NSD уже после подсказки
        assertEquals(listOf("10.0.2.16:41531", "10.0.2.16:33617"), t.peers.value.addressesOf("1").map { "${it.host}:${it.port}" })
    }

    @Test fun loopbackHintWithoutDirectAddressIsNotPublished() = runTest {
        val t = PeerTable { this }
        t.updateServerPeers(listOf(peer("1", host = "127.0.0.1", port = 41531)), "me")
        assertTrue(t.peers.value.isEmpty())
        t.found("mb10-a", peer("1", host = "10.0.2.16", port = 33617))
        assertEquals(listOf(41531, 33617).sorted(), t.peers.value.map { it.port }.sorted())
    }

    @Test fun notReachedMovesAddressToTheEndUntilItWorksAgain() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1", port = 4000))
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1", port = 4001)), "me")
        assertEquals(4001, t.peers.value.first().port)
        t.reportSend("10.10.1.1", 4001, SendOutcome.NOT_REACHED)
        assertEquals(listOf(4000, 4001), t.peers.value.map { it.port })
        assertTrue(t.describe(), t.describe().contains("srv!"))
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1", port = 4001)), "me") // та же подсказка не оживляет адрес
        assertEquals(4000, t.peers.value.first().port)
        t.reportSend("10.10.1.1", 4001, SendOutcome.DELIVERED)
        assertEquals(listOf(4001, 4000), t.peers.value.map { it.port })
    }

    @Test fun unknownOutcomeAndForeignAddressesChangeNothing() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1", port = 4000))
        t.found("nsd2", peer("1", port = 4001))
        val before = t.peers.value
        t.reportSend("10.10.0.1", 4001, SendOutcome.UNKNOWN)
        t.reportSend("10.0.2.2", 2517, SendOutcome.NOT_REACHED)
        assertEquals(before, t.peers.value)
    }

    @Test fun lostServiceTakesAllItsAddresses() = runTest {
        val t = PeerTable { this }
        t.found("mb10-a", peer("1", port = 4000))
        t.found("mb10-a", peer("1", port = 4001))
        t.lost("mb10-a")
        advanceTimeBy(LOST_DEBOUNCE_MS + 1)
        assertTrue(keys(t).isEmpty())
    }

    @Test fun restoreKeepsWhichAddressFailed() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1", port = 4000))
        t.found("nsd2", peer("1", port = 4001))
        t.reportSend("10.10.0.1", 4001, SendOutcome.NOT_REACHED)
        val saved = t.snapshot()
        t.clear()
        t.restore(saved)
        assertEquals(listOf(4000, 4001), t.peers.value.map { it.port })
        t.clear()
    }

    // D2: адрес из входящих и из ответа получателя.
    @Test fun heardPlayerBecomesReachableEvenWithoutNsd() = runTest {
        val t = PeerTable { this }
        t.heard("1", "10.10.0.7", 47100)
        assertEquals(listOf("10.10.0.7:47100"), t.peers.value.map { "${it.host}:${it.port}" })
        assertEquals("", t.players.value.single().callsign) // позывного ещё не знаем
        t.found("mb10-a", peer("1", port = 47100))
        assertEquals("cs1", t.players.value.single().callsign)
        t.clear()
    }

    @Test fun heardAddressComesFirstButDoesNotReviveADeadOne() = runTest {
        val t = PeerTable { this }
        t.found("mb10-a", peer("1", port = 47100))
        t.heard("1", "10.0.2.2", 47100)
        assertEquals("10.0.2.2", t.peers.value.first().host)
        t.reportSend("10.0.2.2", 47100, SendOutcome.NOT_REACHED) // mac-стенд: адрес шлюза, самому не достучаться
        t.heard("1", "10.0.2.2", 47100)
        assertEquals("10.10.0.1", t.peers.value.first().host)
        t.clear()
    }

    @Test fun heardAddressExpiresWithoutNews() = runTest {
        val t = PeerTable { this }
        t.heard("1", "10.10.0.7", 47100)
        advanceTimeBy(HEARD_TTL_MS - 1)
        assertEquals(1, t.peers.value.size)
        t.heard("1", "10.10.0.7", 47100) // новые вести продлевают
        advanceTimeBy(HEARD_TTL_MS - 1)
        assertEquals(1, t.peers.value.size)
        advanceTimeBy(2)
        assertTrue(t.peers.value.isEmpty())
    }

    @Test fun loopbackIsNeverHeard() = runTest {
        val t = PeerTable { this }
        t.heard("1", "127.0.0.1", 47100)
        assertTrue(t.peers.value.isEmpty())
    }

    @Test fun answerFromAnotherPlayerMovesTheAddressToHim() = runTest {
        // DHCP отдал IP ушедшего Alice телефону Bob: по старой записи Alice ответил Bob — «wrong».
        val t = PeerTable { this }
        t.found("mb10-alice", peer("alice", host = "10.10.0.5", port = 47100))
        t.found("mb10-alice2", peer("alice", host = "10.10.0.9", port = 47100))
        t.reportSend("10.10.0.5", 47100, SendOutcome.NOT_REACHED, answeredBy = "bob")
        assertEquals("у Alice этот адрес — последним", "10.10.0.9", t.peers.value.first { it.pubKeyB64 == "alice" }.host)
        assertEquals("10.10.0.5", t.peers.value.first { it.pubKeyB64 == "bob" }.host)
        t.clear()
    }
}
