package com.megablok10.app.ui.nav

import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
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
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Бейджи меню — «Нужны данные» плана миграции UI, перед M3: локальный водяной знак «видел», не сетевой read-receipt. */
@RunWith(RobolectricTestRunner::class)
class ShellBadgesTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private val online = MutableStateFlow(listOf(bob.peer))
    private val directory = PeerDirectory(
        { online.value.map { PeerInfo(it.pubKeyB64, it.callsign, it.faction, "10.0.0.2", 47100) } }, online
    ) { _, _, _, _ -> SendOutcome.NOT_REACHED } // сеть здесь не участвует — только запись в базу
    private val outbox = OutboxStore(db.outboxDao(), directory)
    private val chat = ChatStore(db.chatMessageDao(), outbox, directory)
    private var testClock = 0L
    private val badges = ShellBadges(db.chatMessageDao(), db.callLogDao(), MemoryPrefs(), now = { testClock })

    private suspend fun fromBob(ts: Long, body: String) =
        chat.receive(ChatWireMessage(ChatMessageType.DM, bob.key, bob.callsign, bob.faction, me.publicKeyB64, ts, body))

    @Test fun threadWithNewIncomingMessageCountsAsUnread() = runBlocking {
        fromBob(10, "привет")
        assertEquals(1, badges.unreadChatThreads(me.publicKeyB64).first())
    }

    @Test fun markingChatSeenClearsUntilNextMessage() = runBlocking {
        fromBob(10, "привет")
        testClock = 20
        badges.markChatSeen()
        assertEquals(0, badges.unreadChatThreads(me.publicKeyB64).first())
        fromBob(30, "ещё")
        assertEquals(1, badges.unreadChatThreads(me.publicKeyB64).first())
    }

    @Test fun ownLastMessageInThreadIsNotUnread() = runBlocking {
        fromBob(10, "привет")
        chat.sendDirect(me, bob.key, bob.peer, "ответ")
        assertEquals(0, badges.unreadChatThreads(me.publicKeyB64).first())
    }

    @Test fun missedCallCountsUntilSeen() = runBlocking {
        db.callLogDao().insert(
            CallLogEntity(peerPubKeyB64 = bob.key, peerCallsign = bob.callsign, direction = CallDirection.INCOMING, outcome = CallOutcome.MISSED, startedAt = 10, endedAt = 10)
        )
        assertEquals(1, badges.missedCalls().first())
        testClock = 20
        badges.markCallsSeen()
        assertEquals(0, badges.missedCalls().first())
    }

    @Test fun completedCallsAreNeverCountedAsMissed() = runBlocking {
        db.callLogDao().insert(
            CallLogEntity(peerPubKeyB64 = bob.key, peerCallsign = bob.callsign, direction = CallDirection.OUTGOING, outcome = CallOutcome.COMPLETED, startedAt = 10, endedAt = 40)
        )
        assertEquals(0, badges.missedCalls().first())
    }
}
