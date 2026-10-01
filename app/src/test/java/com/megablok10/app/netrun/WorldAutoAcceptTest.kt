package com.megablok10.app.netrun

import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.app.items.AcceptItem
import com.megablok10.app.items.OutgoingItem
import com.megablok10.app.items.SendItem
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.FakeItemLedger
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.FakePaymentLedger
import com.megablok10.app.testing.TestPlayer
import com.megablok10.app.wallet.AcceptPayment
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Добыча и эдди принимаются сами — только от ключа мира из QR стойки; от остальных карточка ждёт «Принять». */
class WorldAutoAcceptTest {
    private val me = TestPlayer("Призрак")
    private val world = TestPlayer("Мост")
    private val stranger = TestPlayer("Чужой")

    private val myItems = FakeItemLedger(me)
    private val myMoney = FakePaymentLedger(me, balance = 0)
    private val myChat = FakeMessenger(world.peer, stranger.peer)
    private var worldKey: String? = world.key
    private val auto = WorldAutoAccept({ worldKey }, AcceptItem(myItems, myChat), AcceptPayment(myMoney, myChat), myItems, myMoney, myChat)

    private fun dm(from: TestPlayer, body: String, to: TestPlayer = me) =
        ChatWireMessage(ChatMessageType.DM, from.key, from.callsign, "", to.key, 1_000, body)

    private suspend fun itemFrom(sender: TestPlayer, itemId: String): Mb10Qr.ItemTransfer =
        SendItem(FakeItemLedger(sender, itemId), FakeMessenger(me.peer))(sender.identity, OutgoingItem.Shard(itemId), me.key)!!

    private fun payFrom(sender: TestPlayer, amount: Long) =
        FakePaymentLedger(sender).signedTransaction(sender.identity, me.key, amount, "Добыча из Сети")

    @Test fun `loot from the world key is accepted without a tap and the receipt goes back`() = runTest {
        val card = itemFrom(world, "loot-1")

        assertTrue(auto.onDirect(me.identity, dm(world, Mb10QrCodec.encodeItemTransfer(card))))

        assertEquals(setOf("loot-1"), myItems.owned)
        val receipt = Mb10QrCodec.decode(myChat.sent.single().body) as Mb10Qr.Receipt
        assertEquals(card.id, receipt.id)
        assertEquals(world.key, myChat.sent.single().to)
    }

    @Test fun `eddies from the world key are credited and acknowledged`() = runTest {
        val tx = payFrom(world, 120)

        assertTrue(auto.onDirect(me.identity, dm(world, Mb10QrCodec.encodeTransaction(tx))))

        assertEquals(120L, myMoney.balance)
        assertEquals(tx.id, (Mb10QrCodec.decode(myChat.sent.single().body) as Mb10Qr.Receipt).id)
    }

    @Test fun `a repeated card is not credited twice but the receipt is sent again`() = runTest {
        val tx = payFrom(world, 50)
        val card = itemFrom(world, "loot-2")
        val bodies = listOf(Mb10QrCodec.encodeTransaction(tx), Mb10QrCodec.encodeItemTransfer(card))

        repeat(2) { bodies.forEach { auto.onDirect(me.identity, dm(world, it)) } }

        assertEquals(50L, myMoney.balance)
        assertEquals(setOf("loot-2"), myItems.owned)
        assertEquals("по чеку на каждый приход: первый и повторный", 4, myChat.sent.size)
    }

    @Test fun `cards from other players are left for the manual accept`() = runTest {
        val card = itemFrom(stranger, "loot-3")
        val tx = payFrom(stranger, 500)

        assertFalse(auto.onDirect(me.identity, dm(stranger, Mb10QrCodec.encodeItemTransfer(card))))
        assertFalse(auto.onDirect(me.identity, dm(stranger, Mb10QrCodec.encodeTransaction(tx))))

        assertTrue(myItems.owned.isEmpty())
        assertEquals(0L, myMoney.balance)
        assertTrue(myChat.sent.isEmpty())
    }

    @Test fun `without a scanned rack nobody is trusted`() = runTest {
        worldKey = null
        val card = itemFrom(world, "loot-4")

        assertFalse(auto.onDirect(me.identity, dm(world, Mb10QrCodec.encodeItemTransfer(card))))

        assertTrue(myItems.owned.isEmpty())
    }

    @Test fun `the world key cannot pass a stranger's card or a card meant for someone else`() = runTest {
        val strangersCard = itemFrom(stranger, "loot-5")
        val forged = dm(world, Mb10QrCodec.encodeItemTransfer(strangersCard))
        val forOther = dm(world, Mb10QrCodec.encodeItemTransfer(itemFrom(world, "loot-6")), to = stranger)

        assertFalse("карточка не от ключа мира, хоть и пришла его сообщением", auto.onDirect(me.identity, forged))
        assertFalse("сообщение не мне", auto.onDirect(me.identity, forOther))

        assertTrue(myItems.owned.isEmpty())
    }

    @Test fun `chat text and receipts from the world are not cards`() = runTest {
        assertFalse(auto.onDirect(me.identity, dm(world, "привет")))
        assertFalse(auto.onDirect(me.identity, dm(world, Mb10QrCodec.encodeReceipt(Mb10Qr.Receipt("x", world.key, "sig")))))
        assertFalse("общий чат фракции", auto.onDirect(me.identity, dm(world, "привет").copy(type = ChatMessageType.FACTION)))
    }
}
