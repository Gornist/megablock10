package com.megablok10.app.chat

import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.net.LineSocketClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Запросы переотправки на настоящей Room: доставленный без чека перевод находится, и уходит ровно то сообщение, что было. */
@RunWith(RobolectricTestRunner::class)
class CardResenderRoomTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private val chat = ChatStore(db.chatMessageDao(), OutboxStore(db.outboxDao(), LineSocketClient(), { emptyList() }), LineSocketClient(), { emptyList() })
    private val sent = mutableListOf<ChatWireMessage>()
    private var now = 0L
    private val resender get() = CardResender(
        stuck = { before -> wallet.deliveredUnconfirmed(before) + items.deliveredUnconfirmed(before) },
        originalMessage = chat::outgoingCard,
        send = { _, msg -> sent += msg; true },
        peers = { listOf(bob.peer) },
        me = { me.publicKeyB64 },
        now = { now },
    )

    @Test fun deliveredPaymentWithoutReceiptIsResentAsTheSameMessage() = runBlocking {
        wallet.creditShardMoney("s1", 100, "Шард")
        val tx = wallet.signedTransaction(me, bob.key, 30, "за чертёж", "tx-1")
        wallet.recordOutgoingPending(tx, bob.key)
        chat.sendDirectOutcome(me, bob.key, null, Mb10QrCodec.encodeTransaction(tx))   // карточка в своём треде
        db.transactionDao().markDelivered(tx.id)                                          // «записали в сокет»
        now = System.currentTimeMillis()   // часы теста — после создания перевода: его время записано по настоящим часам
        val original = chat.outgoingCard(me.publicKeyB64, bob.key, tx.id)!!

        assertEquals("свежую карточку не трогаем — чек обычно приходит за секунды", 0, resender.resendOnce())
        now += CardResender.GRACE_MS + 1
        assertEquals(1, resender.resendOnce())
        assertEquals(listOf(original), sent)
        assertEquals(Mb10QrCodec.encodeTransaction(tx), sent.single().body)

        db.transactionDao().confirm(tx.id)   // чек пришёл
        assertEquals(0, resender.resendOnce())
    }
}
