package com.megablok10.app.voice

import com.megablok10.app.chat.ChatStore
import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import com.megablok10.app.testing.testPeerDirectory
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.net.LineEnvelope
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Голосовое на настоящей Room: исход отправки → статус, очередь по ссылке (звук из файла), приём «файл до строки», дедуп повтора. */
@RunWith(RobolectricTestRunner::class)
class VoiceMessengerTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private var wire = SendOutcome.DELIVERED
    private val sent = mutableListOf<String>()
    private val online = MutableStateFlow(listOf(bob.peer))
    private val directory = testPeerDirectory(online, { wire }, { sent += it })
    private val store = VoiceStore(java.nio.file.Files.createTempDirectory("voice").toFile())
    private val voice: VoiceMessenger
    private val outbox: OutboxStore

    init {
        lateinit var chat: ChatStore
        outbox = OutboxStore(db.outboxDao(), directory, expand = { VoiceMessenger.expand(it, store) }) { line -> chat.markDelivered(line) }
        chat = ChatStore(db.chatMessageDao(), outbox, directory)
        voice = VoiceMessenger(db.chatMessageDao(), outbox, directory, store)
    }

    private val audio = ByteArray(5_000) { (it % 251).toByte() }
    private val waveform = ByteArray(VoiceLimits.WAVEFORM_BARS) { it.toByte() }
    private fun peer(): OnlinePlayer? = online.value.firstOrNull()
    private suspend fun statuses(): List<Int> = db.chatMessageDao().observeDirect(me.publicKeyB64, bob.key).first().map { it.status }
    private suspend fun send(id: String = "clip-0123456789", peer: OnlinePlayer? = peer(), ms: Long = 4_000) =
        voice.send(me, bob.key, peer, id, ms, waveform, audio)

    /** PeerDirectory оборачивает строку в конверт `MB10TO` — снимаем его и разбираем то, что получил бы приёмник. */
    private fun onWire(): VoiceWireMessage = VoiceProtocol.decode(LineEnvelope.decode(sent.single())!!.line)!!

    @Test fun deliveredClipLeavesFileMarkerAndNoQueue() = runBlocking {
        assertEquals(SendOutcome.DELIVERED, send())
        assertEquals(listOf(MessageStatus.DELIVERED), statuses())
        assertEquals(0, outbox.pending())
        assertTrue(store.exists("clip-0123456789"))
        assertArrayEquals(audio, onWire().audio)
        val row = db.chatMessageDao().observeDirect(me.publicKeyB64, bob.key).first().single()
        assertEquals(VoiceMarker.encode("clip-0123456789", 4_000, waveform), row.body)
    }

    @Test fun offlineClipIsQueuedAsARefAndGoesOutWithAudioFromTheFile() = runBlocking {
        online.value = emptyList()
        assertEquals(SendOutcome.NOT_REACHED, send(peer = null))
        assertEquals(listOf(MessageStatus.PENDING), statuses())
        assertEquals(1, outbox.pending())
        assertTrue("в Room-очереди нет звука", db.outboxDao().due(Long.MAX_VALUE).single().wireLine.length < 600)
        assertTrue(sent.isEmpty())

        online.value = listOf(bob.peer)
        assertEquals(1, outbox.flush())
        assertEquals(listOf(MessageStatus.DELIVERED), statuses())
        assertArrayEquals(audio, onWire().audio)
        assertEquals(0, outbox.pending())
    }

    @Test fun unknownOutcomeIsSentAndQueuedForARetry() = runBlocking {
        wire = SendOutcome.UNKNOWN
        assertEquals(SendOutcome.UNKNOWN, send())
        assertEquals(listOf(MessageStatus.SENT), statuses())
        assertEquals(1, outbox.pending())
        wire = SendOutcome.DELIVERED
        assertEquals(1, outbox.flush())
        assertEquals(listOf(MessageStatus.DELIVERED), statuses())
    }

    @Test fun lostFileDropsTheQueueEntryWithoutPretendingDelivery() = runBlocking {
        online.value = emptyList()
        send(peer = null)
        store.delete("clip-0123456789")
        online.value = listOf(bob.peer)
        outbox.flush()
        assertEquals(0, outbox.pending())
        assertTrue("ничего не ушло", sent.isEmpty())
        assertEquals(listOf(MessageStatus.PENDING), statuses())
    }

    @Test fun badClipsAreRefusedAndLeaveNothing() = runBlocking {
        assertNull(send(ms = VoiceLimits.MAX_DURATION_MS + 1))
        assertNull(send(ms = 0))
        assertNull(voice.send(me, bob.key, peer(), "../../escape-attempt", 1_000, waveform, audio))
        assertNull(voice.send(me, bob.key, peer(), "clip-0123456789", 1_000, waveform, ByteArray(VoiceLimits.MAX_AUDIO_BYTES + 1)))
        assertEquals(emptyList<Int>(), statuses())
        assertTrue(sent.isEmpty())
    }

    @Test fun receivedClipSavesTheFileBeforeTheRowAndRepeatIsADuplicate() = runBlocking {
        val incoming = VoiceWireMessage(bob.key, "Bob", "Малстром", me.publicKeyB64, 5L, "from-bob-0123456", 2_000L, waveform, audio)
        assertTrue(voice.receive(incoming))
        assertArrayEquals(audio, store.read("from-bob-0123456"))
        assertFalse("повтор той же строки из очереди отправителя", voice.receive(incoming))
        val rows = db.chatMessageDao().observeDirect(me.publicKeyB64, bob.key).first()
        assertEquals(1, rows.size)
        assertEquals(MessageStatus.NONE, rows.single().status)
        assertNotNull(VoiceMarker.parse(rows.single().body))
    }
}
