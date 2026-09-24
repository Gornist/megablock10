package com.megablok10.kit.handover

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сторона отправителя: доставка карточки и фиксация по чеку — на журнале в памяти с теми же условными переходами, что в Room. */
class HandoverTest {
    private class FakeJournal : OutgoingJournal {
        val status = mutableMapOf<String, String>()
        val recipient = mutableMapOf<String, String>()
        fun add(id: String, to: String, st: String = HandoverStatus.PENDING) { status[id] = st; recipient[id] = to }
        private fun move(id: String, from: Set<String>, to: String): Int =
            if (status[id] in from) { status[id] = to; 1 } else 0
        override suspend fun markDelivered(id: String) = move(id, setOf(HandoverStatus.PENDING), HandoverStatus.DELIVERED)
        override suspend fun markUndelivered(id: String) = move(id, setOf(HandoverStatus.DELIVERED), HandoverStatus.PENDING)
        override suspend fun confirm(id: String) = move(id, setOf(HandoverStatus.PENDING, HandoverStatus.DELIVERED), HandoverStatus.CONFIRMED)
        override suspend fun recipientOf(id: String) = recipient[id]
    }

    private val journal = FakeJournal()
    private val log = RecordingLog()
    private val handover = Handover(journal, log, tag = "Wallet", eventPrefix = "tx")

    private val bob = Ecdsa.generateKeyPair()
    private val bobKey = Ecdsa.encodeKey(bob.public)
    private fun receiptBy(pair: java.security.KeyPair, id: String) =
        Ecdsa.sign(pair.private, HandoverRules.receiptSignaturePayload(id, Ecdsa.encodeKey(pair.public)))

    @Test fun offlineRecipientKeepsPendingButStillCallsSend() = runTest {
        journal.add("t1", bobKey)
        var sent = 0
        handover.deliver("t1", willSend = false) { sent++; SendOutcome.NOT_REACHED }
        assertEquals(1, sent)
        assertEquals(HandoverStatus.PENDING, journal.status["t1"])
        assertTrue(log.has("I/Wallet tx.deliver id=t1 peerVisible=false"))
    }

    @Test fun statusIsDeliveredWhileTheCardIsInFlight() = runTest {
        journal.add("t1", bobKey)
        var duringSend: String? = null
        handover.deliver("t1", willSend = true) { duringSend = journal.status["t1"]; SendOutcome.DELIVERED }
        assertEquals(HandoverStatus.DELIVERED, duringSend) // отмена во время полёта карточки уже запрещена
        assertEquals(HandoverStatus.DELIVERED, journal.status["t1"])
    }

    @Test fun notReachedRevertsToPendingAndUnknownStaysDelivered() = runTest {
        journal.add("t1", bobKey); journal.add("t2", bobKey)
        handover.deliver("t1", willSend = true) { SendOutcome.NOT_REACHED }
        handover.deliver("t2", willSend = true) { SendOutcome.UNKNOWN }
        assertEquals(HandoverStatus.PENDING, journal.status["t1"])
        assertEquals(HandoverStatus.DELIVERED, journal.status["t2"])
        assertTrue(log.has("tx.deliver id=t1 peerVisible=true outcome=NOT_REACHED status=\"откат в PENDING\""))
    }

    @Test fun receiptFromRecipientConfirmsOnce() = runTest {
        journal.add("t1", bobKey, HandoverStatus.DELIVERED)
        val sig = receiptBy(bob, "t1")
        assertTrue(handover.confirmByReceipt("t1", "t1", bobKey, sig))
        assertEquals(HandoverStatus.CONFIRMED, journal.status["t1"])
        assertFalse(handover.confirmByReceipt("t1", "t1", bobKey, sig)) // повтор чека — уже подтверждено
        assertTrue(log.has("I/Wallet tx.receipt id=t1 confirmed=true"))
    }

    @Test fun receiptFromPendingIsAlsoAccepted() = runTest {
        // Чек мог прийти по карточке, которую отправитель считает недоставленной (обрыв после соединения, досылка).
        journal.add("t1", bobKey, HandoverStatus.PENDING)
        assertTrue(handover.confirmByReceipt("t1", "t1", bobKey, receiptBy(bob, "t1")))
    }

    @Test fun receiptForAnotherTransferOrFromAnotherPlayerIsRejected() = runTest {
        journal.add("t1", bobKey, HandoverStatus.DELIVERED)
        journal.add("t2", bobKey, HandoverStatus.DELIVERED)
        val mallory = Ecdsa.generateKeyPair()
        assertFalse(handover.confirmByReceipt("t1", "t2", bobKey, receiptBy(bob, "t2")))            // чек про другую передачу
        assertFalse(handover.confirmByReceipt("t1", "t1", Ecdsa.encodeKey(mallory.public), receiptBy(mallory, "t1"))) // не адресат
        assertFalse(handover.confirmByReceipt("t1", "t1", bobKey, receiptBy(bob, "t2")))            // подпись над другим id
        assertFalse(handover.confirmByReceipt("x", "x", bobKey, receiptBy(bob, "x")))                // такой передачи нет
        assertEquals(HandoverStatus.DELIVERED, journal.status["t1"])
    }
}
