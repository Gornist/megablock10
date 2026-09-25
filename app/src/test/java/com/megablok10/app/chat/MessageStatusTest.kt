package com.megablok10.app.chat

import com.megablok10.app.data.MessageStatus
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Статус своего личного сообщения на настоящей Room (docs/refactor-plan.md, D3): из исхода отправки и из очереди, только вверх. */
@RunWith(RobolectricTestRunner::class)
class MessageStatusTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private var wire = SendOutcome.DELIVERED
    private val online = MutableStateFlow(listOf(bob.peer))
    private val directory = PeerDirectory(
        { online.value.map { PeerInfo(it.pubKeyB64, it.callsign, it.faction, "10.0.0.2", 47100) } }, online,
    ) { _, _, _, _ -> wire }
    private lateinit var chat: ChatStore
    private val outbox = OutboxStore(db.outboxDao(), directory) { line -> chat.markDelivered(line) }.also {
        chat = ChatStore(db.chatMessageDao(), it, directory)
    }

    private suspend fun statuses(): List<Int> = db.chatMessageDao().observeDirect(me.publicKeyB64, bob.key).first().map { it.status }
    private fun peer(): OnlinePlayer? = online.value.firstOrNull()

    @Test fun statusFollowsTheSendOutcome() = runBlocking {
        chat.sendDirect(me, bob.key, peer(), "дошло")
        wire = SendOutcome.UNKNOWN
        chat.sendDirect(me, bob.key, peer(), "могло дойти")
        wire = SendOutcome.NOT_REACHED
        chat.sendDirect(me, bob.key, peer(), "не дошло")
        assertEquals(listOf(MessageStatus.DELIVERED, MessageStatus.SENT, MessageStatus.PENDING), statuses())
    }

    @Test fun queuedMessageBecomesDeliveredWhenTheQueueSendsIt() = runBlocking {
        online.value = emptyList()
        chat.sendDirect(me, bob.key, null, "пока тебя нет")
        assertEquals(listOf(MessageStatus.PENDING), statuses())
        online.value = listOf(bob.peer)
        wire = SendOutcome.DELIVERED
        assertEquals(1, chat.flushOutbox())
        assertEquals(listOf(MessageStatus.DELIVERED), statuses())
    }

    @Test fun statusNeverGoesDown() = runBlocking {
        chat.sendDirect(me, bob.key, peer(), "прочитано")
        db.chatMessageDao().markReadUpTo(me.publicKeyB64, bob.key, Long.MAX_VALUE)
        val line = ChatProtocol.encode(db.chatMessageDao().observeDirect(me.publicKeyB64, bob.key).first().single().let {
            ChatWireMessage(ChatMessageType.DM, it.fromPubKeyB64, it.fromCallsign, it.faction, it.toPubKeyB64, it.timestamp, it.body)
        })
        chat.markDelivered(line) // поздний ответ очереди
        assertEquals(listOf(MessageStatus.READ), statuses())
    }

    @Test fun incomingMessagesHaveNoStatus() = runBlocking {
        chat.receive(ChatWireMessage(ChatMessageType.DM, bob.key, "Bob", "Малстром", me.publicKeyB64, 5L, "привет"))
        assertEquals(listOf(MessageStatus.NONE), statuses())
    }
}
