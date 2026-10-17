package com.megablok10.app.items

import com.megablok10.app.breach.Daemon
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.FakeItemLedger
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сценарии SendItem/AcceptItem — тот же протокол, что у денег (см. PaymentScenariosTest). */
class ItemScenariosTest {
    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")

    @Test fun shardAndDaemonLeaveTheCollectionAndGoToTheRecipientAsCards() = runTest {
        val ledger = FakeItemLedger(alice, "shard-1", "ghost")
        val chat = FakeMessenger(bob.peer)
        val send = SendItem(ledger, chat)

        val shardCard = send(alice.identity, OutgoingItem.Shard("shard-1"), bob.key)!!
        val daemonCard = send(alice.identity, OutgoingItem.Daemon(Daemon("ghost", "Тень", listOf("1C"))), bob.key)!!

        assertTrue(ledger.owned.isEmpty())
        assertEquals(TransactionStatus.DELIVERED, ledger.status[shardCard.id])
        assertEquals(TransactionStatus.DELIVERED, ledger.status[daemonCard.id])
        assertEquals(listOf(shardCard, daemonCard), chat.sent.map { Mb10QrCodec.decode(it.body) })
        assertTrue(chat.sent.all { it.to == bob.key && it.peer == bob.peer })
    }

    @Test fun offlineTransferStaysPendingAndCanBeCancelled() = runTest {
        val ledger = FakeItemLedger(alice, "shard-1")
        val chat = FakeMessenger(bob.peer)

        val card = SendItem(ledger, chat)(alice.identity, OutgoingItem.Shard("shard-1"), bob.key, offline = true)!!

        assertEquals(TransactionStatus.PENDING, ledger.status[card.id])
        assertNull(chat.sent.single().peer)
        assertTrue(ledger.cancelOutgoing(card.id))
    }

    @Test fun connectionFailureRevertsToPendingButAPossiblyDeliveredCardStaysDelivered() = runTest {
        val ledger = FakeItemLedger(alice, "not-reached", "unknown")
        val chat = FakeMessenger(bob.peer)

        chat.outcome = SendOutcome.NOT_REACHED
        val notReached = SendItem(ledger, chat)(alice.identity, OutgoingItem.Shard("not-reached"), bob.key)!!
        chat.outcome = SendOutcome.UNKNOWN
        val unknown = SendItem(ledger, chat)(alice.identity, OutgoingItem.Shard("unknown"), bob.key)!!

        assertEquals(TransactionStatus.PENDING, ledger.status[notReached.id])
        // мог дойти — отменять нельзя: иначе предмет окажется и в коллекции отправителя, и у получателя
        assertEquals(TransactionStatus.DELIVERED, ledger.status[unknown.id])
        assertFalse(ledger.cancelOutgoing(unknown.id))
        assertTrue(ledger.cancelOutgoing(notReached.id))
    }

    @Test fun missingItemSendsNothing() = runTest {
        val chat = FakeMessenger(bob.peer)

        assertNull(SendItem(FakeItemLedger(alice), chat)(alice.identity, OutgoingItem.Shard("нет-такого"), bob.key))

        assertTrue(chat.sent.isEmpty())
    }

    @Test fun acceptingPutsTheItemIntoTheCollectionAndTheReceiptConfirmsTheSendersTransfer() = runTest {
        val alicesLedger = FakeItemLedger(alice, "shard-1")
        val card = SendItem(alicesLedger, FakeMessenger(bob.peer))(alice.identity, OutgoingItem.Shard("shard-1"), bob.key)!!

        val bobsLedger = FakeItemLedger(bob)
        val bobsChat = FakeMessenger(alice.peer)
        val accept = AcceptItem(bobsLedger, bobsChat)
        assertTrue(accept(bob.identity, card))
        assertFalse("повторное «Принять» не размножает предмет и не шлёт второй чек", accept(bob.identity, card))

        assertEquals(setOf("shard-1"), bobsLedger.owned)
        val reply = bobsChat.sent.single()
        assertEquals(alice.key, reply.to)
        assertTrue(alicesLedger.verifyAndConfirmReceipt(card.id, Mb10QrCodec.decode(reply.body) as Mb10Qr.Receipt))
        assertEquals(TransactionStatus.CONFIRMED, alicesLedger.status[card.id])
    }
}
