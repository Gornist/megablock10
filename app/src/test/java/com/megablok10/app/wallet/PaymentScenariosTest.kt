package com.megablok10.app.wallet

import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.FakePaymentLedger
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сценарии SendPayment/AcceptPayment поверх настоящего протокола kit handover и настоящих подписей. */
class PaymentScenariosTest {
    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")

    @Test fun paymentToAVisiblePlayerIsDebitedDeliveredAndSentAsATransactionCard() = runTest {
        val ledger = FakePaymentLedger(alice, balance = 100)
        val chat = FakeMessenger(bob.peer)
        var statusAtSend: String? = null
        chat.onSend = { statusAtSend = ledger.status.values.single() }

        val tx = SendPayment(ledger, chat)(alice.identity, bob.key, 30, "за пиво", id = "tx-1")!!

        assertEquals(70, ledger.balance)
        assertEquals("статус DELIVERED ставится ДО отправки — иначе отмену можно провести во время полёта карточки", TransactionStatus.DELIVERED, statusAtSend)
        assertEquals(TransactionStatus.DELIVERED, ledger.status["tx-1"])
        val sent = chat.sent.single()
        assertEquals(bob.key, sent.to)
        assertEquals(bob.peer, sent.peer)
        assertEquals(tx, Mb10QrCodec.decode(sent.body))
        assertEquals(Mb10Qr.Transaction("tx-1", alice.key, bob.key, 30, "за пиво", tx.signatureB64), tx)
    }

    @Test fun recipientOutOfSightKeepsThePaymentPendingAndCancellable() = runTest {
        val ledger = FakePaymentLedger(alice)
        val chat = FakeMessenger()   // Боба не видно

        SendPayment(ledger, chat)(alice.identity, bob.key, 10, "", id = "tx-1")

        assertEquals(TransactionStatus.PENDING, ledger.status["tx-1"])
        assertNull("карточка ложится только в свой тред — адреса нет", chat.sent.single().peer)
        assertTrue(ledger.cancelOutgoing("tx-1"))
    }

    @Test fun offlineFlagTreatsAVisibleRecipientAsOutOfSight() = runTest {
        val ledger = FakePaymentLedger(alice)
        val chat = FakeMessenger(bob.peer)

        SendPayment(ledger, chat)(alice.identity, bob.key, 10, "", id = "tx-1", offline = true)

        assertEquals(TransactionStatus.PENDING, ledger.status["tx-1"])
        assertNull(chat.sent.single().peer)
    }

    @Test fun connectionFailureRevertsToPendingButAPossiblyDeliveredCardStaysDelivered() = runTest {
        val ledger = FakePaymentLedger(alice)
        val chat = FakeMessenger(bob.peer)

        chat.outcome = SendOutcome.NOT_REACHED
        SendPayment(ledger, chat)(alice.identity, bob.key, 10, "", id = "not-reached")
        chat.outcome = SendOutcome.UNKNOWN
        SendPayment(ledger, chat)(alice.identity, bob.key, 10, "", id = "unknown")

        assertEquals(TransactionStatus.PENDING, ledger.status["not-reached"])
        assertEquals("мог дойти — отменять нельзя", TransactionStatus.DELIVERED, ledger.status["unknown"])
    }

    @Test fun refusedDebitSendsNothing() = runTest {
        val ledger = FakePaymentLedger(alice, balance = 5)
        val chat = FakeMessenger(bob.peer)

        assertNull(SendPayment(ledger, chat)(alice.identity, bob.key, 10, ""))

        assertEquals(5, ledger.balance)
        assertTrue(chat.sent.isEmpty())
    }

    @Test fun acceptingCreditsAndAnswersTheSenderWithAReceiptThatConfirmsThePayment() = runTest {
        val alicesLedger = FakePaymentLedger(alice, balance = 100)
        val alicesChat = FakeMessenger(bob.peer)
        val tx = SendPayment(alicesLedger, alicesChat)(alice.identity, bob.key, 25, "", id = "tx-1")!!

        val bobsLedger = FakePaymentLedger(bob, balance = 0)
        val bobsChat = FakeMessenger(alice.peer)
        assertTrue(AcceptPayment(bobsLedger, bobsChat)(bob.identity, tx))

        assertEquals(25, bobsLedger.balance)
        val reply = bobsChat.sent.single()
        assertEquals("чек — отправителю, а не тому, чей тред открыт", alice.key, reply.to)
        assertEquals(alice.peer, reply.peer)
        val receipt = Mb10QrCodec.decode(reply.body) as Mb10Qr.Receipt
        assertTrue(alicesLedger.verifyAndConfirmReceipt(tx.id, receipt))
        assertEquals(TransactionStatus.CONFIRMED, alicesLedger.status["tx-1"])
    }

    @Test fun receiptWaitsInTheThreadWhenTheSenderIsOutOfSight() = runTest {
        val tx = FakePaymentLedger(alice).signedTransaction(alice.identity, bob.key, 5, "", "tx-1")
        val bobsChat = FakeMessenger()

        assertTrue(AcceptPayment(FakePaymentLedger(bob, 0), bobsChat)(bob.identity, tx))

        assertNull(bobsChat.sent.single().peer)
    }

    @Test fun refusedOrRepeatedAcceptSendsNoReceipt() = runTest {
        val tx = FakePaymentLedger(alice).signedTransaction(alice.identity, bob.key, 5, "", "tx-1")
        val bobsLedger = FakePaymentLedger(bob, 0)
        val bobsChat = FakeMessenger(alice.peer)
        val accept = AcceptPayment(bobsLedger, bobsChat)

        assertTrue(accept(bob.identity, tx))
        assertFalse("повторное «Принять» ничего не зачисляет", accept(bob.identity, tx))
        assertFalse("чужую карточку не принять", AcceptPayment(FakePaymentLedger(alice, 0), FakeMessenger())(alice.identity, tx))

        assertEquals(5, bobsLedger.balance)
        assertNotNull(bobsChat.sent.singleOrNull())
    }
}
