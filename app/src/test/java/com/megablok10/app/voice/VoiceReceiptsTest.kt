package com.megablok10.app.voice

import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.chat.ReadReceiptSetting
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import com.megablok10.app.testing.testPeerDirectory
import com.megablok10.kit.net.LineEnvelope
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Синие ✓✓ у голосовых: «прослушал» уходит автору один раз, принимается только по своему id и слушателю, MB10READ голосовые не трогает. */
@RunWith(RobolectricTestRunner::class)
class VoiceReceiptsTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private var wire = SendOutcome.DELIVERED
    private val sent = mutableListOf<String>()
    private val online = MutableStateFlow(listOf(bob.peer))
    private val directory = testPeerDirectory(online, { wire }, { sent += it })
    private val outbox = OutboxStore(db.outboxDao(), directory)
    private val setting = ReadReceiptSetting(prefs)
    private val receipts = VoiceReceipts(db.chatMessageDao(), directory, outbox, setting) { me.publicKeyB64 }
    private val dao get() = db.chatMessageDao()
    private val waveform = ByteArray(VoiceLimits.WAVEFORM_BARS)

    private suspend fun row(from: String, to: String, id: String, ts: Long = 100) =
        dao.insert(ChatMessageEntity(type = "DM", fromPubKeyB64 = from, fromCallsign = "x", faction = "f", toPubKeyB64 = to, body = VoiceMarker.encode(id, 3_000, waveform), timestamp = ts))

    private fun onWire() = VoiceListenProtocol.decode(LineEnvelope.decode(sent.single())!!.line)!!

    @Test fun protocolRoundTripAndValidation() {
        val r = VoiceListened("LISTENER+/=", "AUTHOR+/=", "clip-0123456789")
        assertEquals(r, VoiceListenProtocol.decode(VoiceListenProtocol.encode(r)))
        assertNull(VoiceListenProtocol.decode(VoiceListenProtocol.encode(r).replace("clip-0123456789", "../../evil")))
        assertNull(VoiceListenProtocol.decode(VoiceListenProtocol.encode(r).replace(":v1:", ":v2:")))
        assertNull(VoiceListenProtocol.decode("MB10READ:v1:a:b:5"))
        assertNull(VoiceListenProtocol.decode("MB10LISTEN:v1::AUTHOR:clip-0123456789"))
    }

    @Test fun firstPlayMarksListenedAndTellsTheAuthorOnce() = runBlocking {
        val id = row(bob.key, me.publicKeyB64, "from-bob-0123456")
        receipts.onPlayed(id)
        assertEquals(MessageStatus.LISTENED, dao.byId(id)!!.status)
        assertEquals(VoiceListened(me.publicKeyB64, bob.key, "from-bob-0123456"), onWire())
        receipts.onPlayed(id)
        assertEquals("повторное воспроизведение отчёт не шлёт", 1, sent.size)
    }

    @Test fun unreachableAuthorGetsTheReceiptFromTheQueue() = runBlocking {
        wire = SendOutcome.NOT_REACHED
        val id = row(bob.key, me.publicKeyB64, "from-bob-0123456")
        receipts.onPlayed(id)
        assertEquals(1, outbox.pending())
    }

    @Test fun switchedOffReceiptsStayLocal() = runBlocking {
        setting.set(false)
        val id = row(bob.key, me.publicKeyB64, "from-bob-0123456")
        receipts.onPlayed(id)
        assertEquals("точка гаснет и без отчёта", MessageStatus.LISTENED, dao.byId(id)!!.status)
        assertTrue(sent.isEmpty())
        assertEquals(0, outbox.pending())
    }

    @Test fun ownClipPlaybackDoesNotReportToMyself() = runBlocking {
        val id = row(me.publicKeyB64, bob.key, "mine-bob-0123456")
        receipts.onPlayed(id)
        assertTrue(sent.isEmpty())
    }

    @Test fun receivedReceiptRaisesOnlyTheMatchingOwnClip() = runBlocking {
        val mine = row(me.publicKeyB64, bob.key, "mine-bob-0123456")
        val other = row(me.publicKeyB64, bob.key, "mine-bob-9999999", ts = 200)
        val toCarol = row(me.publicKeyB64, "CAROL", "mine-bob-0123456", ts = 300) // тот же id у другого адресата — не засчитывается
        dao.raiseStatus(mine, MessageStatus.DELIVERED)
        receipts.onReceived(me.publicKeyB64, VoiceListened(bob.key, me.publicKeyB64, "mine-bob-0123456"))
        assertEquals(MessageStatus.LISTENED, dao.byId(mine)!!.status)
        assertEquals(MessageStatus.NONE, dao.byId(other)!!.status)
        assertEquals(MessageStatus.NONE, dao.byId(toCarol)!!.status)
        receipts.onReceived(me.publicKeyB64, VoiceListened(bob.key, "SOMEONE-ELSE", "mine-bob-9999999")) // не мне
        assertEquals(MessageStatus.NONE, dao.byId(other)!!.status)
    }

    @Test fun readReceiptDoesNotTouchVoiceClips() = runBlocking {
        val voice = row(me.publicKeyB64, bob.key, "mine-bob-0123456", ts = 100)
        val text = dao.insert(ChatMessageEntity(type = "DM", fromPubKeyB64 = me.publicKeyB64, fromCallsign = "x", faction = "f", toPubKeyB64 = bob.key, body = "привет", timestamp = 110))
        dao.markReadUpTo(me.publicKeyB64, bob.key, 1_000)
        assertEquals("голосовое ждёт «прослушано»", MessageStatus.NONE, dao.byId(voice)!!.status)
        assertEquals(MessageStatus.READ, dao.byId(text)!!.status)
    }
}
