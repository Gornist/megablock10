package com.megablok10.app.netrun

import com.megablok10.app.breach.Daemon
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.FakeItemLedger
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Вход в «Сеть» со стороны телефона: карточки демонов Мосту, запрос, подписанный ответ. Мост здесь — только его ключ мира. */
@OptIn(ExperimentalCoroutinesApi::class)
class NetrunEntryTest {
    private val me = TestPlayer("Призрак")
    private val world = TestPlayer("Мост")
    private val rack = Mb10Qr.Rack("t03", "10.10.0.10", 7411, world.key, "Подвал, стойка 3")
    private val ghost = Daemon("d1", "Призрак", listOf("1C", "BD"))
    private val miner = Daemon("d2", "Шахтёр", listOf("55", "E9"))

    private class Rig(val me: TestPlayer, val world: TestPlayer, scope: TestScope, bridgeReachable: Boolean = true, vararg owned: String) {
        val ledger = FakeItemLedger(me, *owned)
        val messenger = FakeMessenger(*(if (bridgeReachable) arrayOf(world.peer) else emptyArray()))
        val store = NetrunStore(MemoryPrefs())
        val lines = mutableListOf<String>()
        val peers = mutableListOf<PeerInfo>()
        val entry = NetrunEntry(
            store, ledger, messenger,
            sendLine = { _, line -> lines += line; SendOutcome.DELIVERED },
            addPeer = { peers += it }, sign = me::sign, work = scope,
            now = { scope.testScheduler.currentTime }, newRid = { "e-test" }, retryMs = 1_000, waitMs = 10_000, io = StandardTestDispatcher(scope.testScheduler),
        )
    }

    private fun TestScope.rig(reachable: Boolean = true) = Rig(me, world, this, reachable, "d1", "d2")

    private fun reply(rid: String, ok: Boolean, signer: TestPlayer = world, session: String = "s_1", code: String = "", msg: String = ""): EnterReply {
        val unsigned = EnterReply(rid, ok, session, code, msg, "")
        return unsigned.copy(signature = signer.sign(NetrunWire.enteredSignedBytes(unsigned)))
    }

    @Test fun `cards go to the world key, the signed request follows and the signed reply connects`() = runTest {
        val r = rig()

        r.entry.enter(me.identity, rack, listOf(ghost, miner), protectedId = "d2")
        testScheduler.runCurrent()

        assertEquals("адрес Моста — статический пир из QR", listOf(PeerInfo(world.key, "Мост", "", "10.10.0.10", 7411)), r.peers)
        val cards = r.messenger.sent.map { Mb10QrCodec.decode(it.body) as Mb10Qr.ItemTransfer }
        assertEquals(2, cards.size)
        assertTrue(cards.all { it.toPubKeyB64 == world.key && r.ledger.status[it.id] == TransactionStatus.DELIVERED })
        assertTrue("демоны ушли из коллекции", r.ledger.owned.isEmpty())

        val request = NetrunWire.decodeEnter(r.lines.first())!!
        assertEquals("e-test", request.rid)
        assertEquals("t03", request.terminal)
        assertEquals(cards.map { it.id }, request.transfers)
        assertEquals("защищённый слот — карточка второго демона", cards[1].id, request.protectedTransfer)
        assertTrue(Ecdsa.verify(me.key, NetrunWire.enterSignedBytes(request), request.signature))
        assertEquals(NetrunEntryState.Waiting(rack), r.entry.state.value)

        r.entry.onEntered(reply("e-test", ok = true))
        assertEquals(NetrunEntryState.Connected(rack, "s_1"), r.entry.state.value)
        assertNull("запрос закрыт — повторять нечего", r.store.attempt())
    }

    @Test fun `unsigned, forged and foreign replies change nothing`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")

        r.entry.onEntered(reply("e-test", ok = true, signer = me))
        r.entry.onEntered(reply("e-other", ok = true))
        r.entry.onEntered(reply("e-test", ok = true).copy(session = "s_подмена"))

        assertEquals(NetrunEntryState.Waiting(rack), r.entry.state.value)
        assertNotNull(r.store.attempt())
        r.entry.onEntered(reply("e-test", ok = true))
        assertTrue(r.entry.state.value is NetrunEntryState.Connected)
    }

    @Test fun `a refusal from the bridge is shown and a repeated reply is ignored`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")

        r.entry.onEntered(reply("e-test", ok = false, session = "", code = "session_state", msg = "терминал занят"))
        val failed = r.entry.state.value as NetrunEntryState.Failed
        assertTrue(failed.text.contains("терминал занят"))

        r.entry.onEntered(reply("e-test", ok = true))
        assertEquals("второй, противоречащий ответ не принимается", failed, r.entry.state.value)
    }

    @Test fun `the request repeats with the same rid until the reply comes and then stops`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")
        testScheduler.advanceTimeBy(2_500)
        testScheduler.runCurrent()
        val before = r.lines.size
        assertTrue("повторы: $before", before >= 3)
        assertEquals(1, r.lines.map { NetrunWire.decodeEnter(it)!!.rid }.toSet().size)

        r.entry.onEntered(reply("e-test", ok = true))
        testScheduler.advanceTimeBy(5_000)
        testScheduler.runCurrent()
        assertTrue("после ответа повторов нет", r.lines.size <= before + 1)
    }

    @Test fun `no answer within the wait time offers a manual retry`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")
        testScheduler.advanceTimeBy(11_000)
        testScheduler.runCurrent()
        assertEquals(NetrunEntryState.Waiting(rack, timedOut = true), r.entry.state.value)

        r.entry.retry()
        assertEquals(NetrunEntryState.Waiting(rack), r.entry.state.value)
        r.entry.onEntered(reply("e-test", ok = true))
        assertTrue(r.entry.state.value is NetrunEntryState.Connected)
    }

    @Test fun `an unreachable bridge returns the daemon and sends no request`() = runTest {
        val r = rig(reachable = false)

        r.entry.enter(me.identity, rack, listOf(ghost), "d1")

        assertTrue(r.entry.state.value is NetrunEntryState.Failed)
        assertTrue("карточка отменена, не висит в PENDING", r.ledger.status.isEmpty())
        assertTrue(r.lines.isEmpty())
        assertNull(r.store.attempt())
    }

    @Test fun `unknown outcome of a card is not rolled back and the request still goes`() = runTest {
        val r = rig()
        r.messenger.outcome = SendOutcome.UNKNOWN

        r.entry.enter(me.identity, rack, listOf(ghost), "d1")
        testScheduler.runCurrent()

        assertEquals(NetrunEntryState.Waiting(rack), r.entry.state.value)
        assertTrue("могло дойти — демон не возвращается", "d1" !in r.ledger.owned)
        assertEquals(1, NetrunWire.decodeEnter(r.lines.first())!!.transfers.size)
    }

    @Test fun `bad choices are refused before anything is sent`() = runTest {
        val r = rig()
        val starter = Daemon("datamine_v1", "Datamine V1", listOf("1C", "55"))
        val big = Daemon("d3", "Большой", List(7) { "AA" })

        r.entry.enter(me.identity, rack, emptyList(), "")
        assertTrue(r.entry.state.value is NetrunEntryState.Failed)
        r.entry.enter(me.identity, rack, listOf(ghost), "d2")
        assertTrue("защищённый вне деки", r.entry.state.value is NetrunEntryState.Failed)
        r.entry.enter(me.identity, rack, listOf(starter), starter.id)
        assertTrue("стартовый демон", r.entry.state.value is NetrunEntryState.Failed)
        r.entry.enter(me.identity, rack, listOf(big), "d3")
        assertTrue("не помещается в RAM", r.entry.state.value is NetrunEntryState.Failed)

        assertTrue(r.messenger.sent.isEmpty() && r.lines.isEmpty())
    }

    @Test fun `a restarted phone still waits for the reply of its request`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")

        val restarted = NetrunEntry(
            r.store, r.ledger, r.messenger, { _, _ -> SendOutcome.DELIVERED }, {}, me::sign, this,
            now = { testScheduler.currentTime }, retryMs = 1_000, waitMs = 10_000, io = StandardTestDispatcher(testScheduler),
        )
        assertEquals(NetrunEntryState.Waiting(rack, timedOut = true), restarted.state.value)
        restarted.onEntered(reply("e-test", ok = true))
        assertTrue(restarted.state.value is NetrunEntryState.Connected)
    }

    @Test fun `the reply is checked against the rack of the request, not the last scanned one`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")
        val other = TestPlayer("Чужой мир")
        r.entry.onRackScanned(Mb10Qr.Rack("t09", "10.10.0.99", 7411, other.key))

        r.entry.onEntered(reply("e-test", ok = true, signer = other))
        assertEquals(NetrunEntryState.Waiting(rack), r.entry.state.value)
        assertEquals(rack, r.store.attempt()!!.rack)

        r.entry.onEntered(reply("e-test", ok = true))
        assertEquals(NetrunEntryState.Connected(rack, "s_1"), r.entry.state.value)
    }

    @Test fun `session reset drops the state of the previous character`() = runTest {
        val r = rig()
        r.entry.enter(me.identity, rack, listOf(ghost), "d1")

        r.entry.reset()

        assertEquals(NetrunEntryState.Idle, r.entry.state.value)
        assertNull(r.store.attempt())
        assertNull(r.store.worldPub())
    }
}
