package com.megablok10.app.voice

import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Запрос «следующее непрослушанное голосовое от собеседника» (автопроигрывание) на настоящей Room. */
@RunWith(RobolectricTestRunner::class)
class VoiceListenedQueryTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private val carol = TestPlayer("Carol")
    private val dao get() = db.chatMessageDao()
    private val waveform = ByteArray(VoiceLimits.WAVEFORM_BARS)

    private suspend fun voiceRow(from: String, to: String, ts: Long, id: String) =
        dao.insert(ChatMessageEntity(type = "DM", fromPubKeyB64 = from, fromCallsign = "x", faction = "f", toPubKeyB64 = to, body = VoiceMarker.encode(id, 3_000, waveform), timestamp = ts))

    @Test fun nextUnlistenedIsTheEarliestLaterIncomingVoiceFromThatPeer() = runBlocking {
        val a = voiceRow(bob.key, me.publicKeyB64, 100, "voice-aaaaaaaa")
        val b = voiceRow(bob.key, me.publicKeyB64, 200, "voice-bbbbbbbb")
        val c = voiceRow(bob.key, me.publicKeyB64, 300, "voice-cccccccc")
        voiceRow(carol.key, me.publicKeyB64, 150, "voice-dddddddd") // другой собеседник
        voiceRow(me.publicKeyB64, bob.key, 250, "voice-eeeeeeee")   // своё
        dao.insert(ChatMessageEntity(type = "DM", fromPubKeyB64 = bob.key, fromCallsign = "Bob", faction = "f", toPubKeyB64 = me.publicKeyB64, body = "обычный текст", timestamp = 260))

        assertEquals(b, dao.nextUnlistenedVoice(me.publicKeyB64, bob.key, after = 100)?.id)
        dao.raiseStatus(b, MessageStatus.LISTENED)
        assertEquals("прослушанное пропускается", c, dao.nextUnlistenedVoice(me.publicKeyB64, bob.key, after = 100)?.id)
        assertEquals(a, dao.nextUnlistenedVoice(me.publicKeyB64, bob.key, after = 0)?.id)
        dao.raiseStatus(c, MessageStatus.LISTENED)
        assertNull(dao.nextUnlistenedVoice(me.publicKeyB64, bob.key, after = 100))
    }

    @Test fun listenedNeverGoesDownAndTrackIsBuiltFromTheRow() = runBlocking {
        val id = voiceRow(bob.key, me.publicKeyB64, 100, "voice-aaaaaaaa")
        dao.raiseStatus(id, MessageStatus.LISTENED)
        dao.raiseStatus(id, MessageStatus.DELIVERED)
        val row = dao.nextUnlistenedVoice(me.publicKeyB64, bob.key, 0)
        assertNull("статус «прослушано» поздним статусом не сбить", row)
        val own = voiceRow(me.publicKeyB64, bob.key, 400, "voice-ffffffff")
        val ownRow = ChatMessageEntity(own, "DM", me.publicKeyB64, "x", "f", bob.key, VoiceMarker.encode("voice-ffffffff", 3_000, waveform), 400)
        val track = ownRow.voiceTrack(me.publicKeyB64)!!
        assertEquals(bob.key, track.peerKey)
        assertEquals(false, track.incoming)
        assertEquals("voice-ffffffff", track.clipId)
    }
}
