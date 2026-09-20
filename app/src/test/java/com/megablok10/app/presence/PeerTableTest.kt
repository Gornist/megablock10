package com.megablok10.app.presence

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
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
        assertEquals("10.10.0.99", t.peers.value.single().host)
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

    @Test fun serverPeersFillGapsButNeverDuplicateNsd() = runTest {
        val t = PeerTable { this }
        t.found("nsd", peer("1"))
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1"), peer("2"), peer("me")), "me")
        assertEquals(listOf("1", "2"), keys(t))
        assertEquals("10.10.0.1", t.peers.value.first { it.pubKeyB64 == "1" }.host) // адрес NSD главнее серверного
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

    @Test fun serverPeerIsDroppedOnceNsdFindsSamePlayer() = runTest {
        val t = PeerTable { this }
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1")), "me")
        t.found("nsd", peer("1"))
        t.updateServerPeers(listOf(peer("1", host = "10.10.1.1")), "me")
        assertEquals(1, t.peers.value.size)
        assertEquals("10.10.0.1", t.peers.value.single().host)
    }
}
