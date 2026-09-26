package com.megablok10.app.chat

import com.megablok10.app.data.MessageStatus
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Отчёты о прочтении (docs/refactor-plan.md, D4): водяной знак «до T», один раз на знак, в очередь, если автора не видно. */
@RunWith(RobolectricTestRunner::class)
class ReadReceiptsTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private var wire = SendOutcome.DELIVERED
    private val sent = mutableListOf<String>()
    private val online = MutableStateFlow(listOf(bob.peer))
    private val directory = PeerDirectory(
        { online.value.map { PeerInfo(it.pubKeyB64, it.callsign, it.faction, "10.0.0.2", 47100) } }, online,
    ) { _, _, line, _ -> sent += line; wire }
    private val outbox = OutboxStore(db.outboxDao(), directory)
    private val chat = ChatStore(db.chatMessageDao(), outbox, directory)
    private val setting = ReadReceiptSetting(MemoryPrefs())
    private val receipts = ReadReceipts(db.chatMessageDao(), directory, outbox, setting)

    private suspend fun thread() = db.chatMessageDao().observeDirect(me.publicKeyB64, bob.key).first()
    private suspend fun fromBob(ts: Long, body: String) =
        chat.receive(ChatWireMessage(ChatMessageType.DM, bob.key, "Bob", "Малстром", me.publicKeyB64, ts, body))
    private fun receiptsSent() = sent.mapNotNull { ReadReceiptProtocol.decode(it.substringAfter("MB10TO:v1:").split(":", limit = 4)[3]) }

    @Test fun protocolRoundTripAndGarbage() {
        val r = ReadReceipt("reader/+=", "author", 1_234L)
        assertEquals(r, ReadReceiptProtocol.decode(ReadReceiptProtocol.encode(r)))
        assertNull(ReadReceiptProtocol.decode("MB10READ:v9:a:b:1"))
        assertNull(ReadReceiptProtocol.decode("MB10READ:v1:a:b:когда"))
    }

    @Test fun seeingTheThreadSendsTheLatestWatermarkOnce() = runBlocking {
        fromBob(10, "раз"); fromBob(20, "два")
        receipts.onThreadShown(me.publicKeyB64, bob.key, thread())
        receipts.onThreadShown(me.publicKeyB64, bob.key, thread()) // лента обновилась, новых от Bob нет
        assertEquals(listOf(ReadReceipt(me.publicKeyB64, bob.key, 20)), receiptsSent())
        fromBob(30, "три")
        receipts.onThreadShown(me.publicKeyB64, bob.key, thread())
        assertEquals(30L, receiptsSent().last().upTo)
    }

    @Test fun ownMessagesDoNotCountAsRead() = runBlocking {
        chat.sendDirect(me, bob.key, bob.peer, "моё")
        sent.clear()
        receipts.onThreadShown(me.publicKeyB64, bob.key, thread())
        assertTrue(receiptsSent().isEmpty())
    }

    @Test fun undeliveredReceiptWaitsInTheQueue() = runBlocking {
        fromBob(10, "раз")
        wire = SendOutcome.NOT_REACHED
        receipts.onThreadShown(me.publicKeyB64, bob.key, thread())
        assertEquals(1, outbox.pending())
    }

    @Test fun switchedOffSendsNothing() = runBlocking {
        fromBob(10, "раз")
        setting.set(false)
        receipts.onThreadShown(me.publicKeyB64, bob.key, thread())
        assertTrue(sent.isEmpty())
    }

    @Test fun receivedReceiptMarksMyMessagesUpToTheWatermark() = runBlocking {
        chat.sendDirect(me, bob.key, bob.peer, "первое")
        val t1 = thread().single().timestamp
        receipts.onReceived(me.publicKeyB64, ReadReceipt(bob.key, me.publicKeyB64, t1))
        Thread.sleep(2) // второе — позже водяного знака
        chat.sendDirect(me, bob.key, bob.peer, "второе")
        assertEquals(listOf(MessageStatus.READ, MessageStatus.DELIVERED), thread().map { it.status })
        receipts.onReceived(me.publicKeyB64, ReadReceipt(bob.key, "кто-то другой", Long.MAX_VALUE)) // не про мои — мимо
        assertEquals(listOf(MessageStatus.READ, MessageStatus.DELIVERED), thread().map { it.status })
    }
}
