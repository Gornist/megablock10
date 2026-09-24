package com.megablok10.app.chat

import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.items.OutgoingItem
import com.megablok10.app.items.SendItem
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.FakeItemLedger
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.FakePaymentLedger
import com.megablok10.app.testing.TestPlayer
import com.megablok10.app.wallet.SendPayment
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** Чек, пришедший по сети, подтверждает перевод или передачу у отправителя сразу при приёме — где бы он ни был в интерфейсе. */
class ReceiptConfirmerTest {
    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val payments = FakePaymentLedger(alice)
    private val items = FakeItemLedger(alice, "shard-1")
    private val confirmer = ReceiptConfirmer(payments, items)

    private fun dm(from: TestPlayer, body: String, type: ChatMessageType = ChatMessageType.DM) =
        ChatWireMessage(type, from.key, from.callsign, from.faction, alice.key, 1L, body)

    @Test fun incomingReceiptConfirmsTheMatchingPaymentOrItem() = runTest {
        val chat = FakeMessenger(bob.peer)
        val tx = SendPayment(payments, chat)(alice.identity, bob.key, 10, "", id = "tx-1")!!
        val card = SendItem(items, chat)(alice.identity, OutgoingItem.Shard("shard-1"), bob.key)!!
        val bobsPayments = FakePaymentLedger(bob)
        val bobsItems = FakeItemLedger(bob)

        confirmer.onIncoming(dm(bob, Mb10QrCodec.encodeReceipt(bobsPayments.buildReceipt(bob.identity, tx.id))))
        confirmer.onIncoming(dm(bob, Mb10QrCodec.encodeReceipt(bobsItems.buildReceipt(bob.identity, card.id))))

        assertEquals(TransactionStatus.CONFIRMED, payments.status[tx.id])
        assertEquals(TransactionStatus.CONFIRMED, items.status[card.id])
    }

    @Test fun receiptInAFactionMessageOrFromTheWrongPlayerConfirmsNothing() = runTest {
        val tx = SendPayment(payments, FakeMessenger(bob.peer))(alice.identity, bob.key, 10, "", id = "tx-1")!!
        val mallory = TestPlayer("Mallory")

        confirmer.onIncoming(dm(bob, Mb10QrCodec.encodeReceipt(FakePaymentLedger(bob).buildReceipt(bob.identity, tx.id)), ChatMessageType.FACTION))
        confirmer.onIncoming(dm(mallory, Mb10QrCodec.encodeReceipt(FakePaymentLedger(mallory).buildReceipt(mallory.identity, tx.id))))
        confirmer.onIncoming(dm(bob, "просто текст"))

        assertEquals(TransactionStatus.DELIVERED, payments.status[tx.id])
    }
}
