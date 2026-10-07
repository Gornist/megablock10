package com.megablok10.app.voice

import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Автопроигрывание на настоящих запросах Room, а не на подмене «следующего»: собранная как в AppGraph цепочка VoicePlayer → nextUnlistenedTrack → markListened
 * после окончания клипа сама запускает следующее непрослушанное от того же собеседника.
 */
@RunWith(RobolectricTestRunner::class)
class VoiceAutoplayRoomTest : RoomTest() {
    private class Engine : ClipPlayer {
        override var onInterrupted: () -> Unit = {}
        override var onCompleted: () -> Unit = {}
        val played = mutableListOf<String>()
        override fun play(file: File, startMs: Long, speed: Float): Boolean { played += file.nameWithoutExtension; return true }
        override fun pause() = Unit
        override fun resume() = Unit
        override fun seekTo(ms: Long) = Unit
        override fun setSpeed(speed: Float) = Unit
        override fun positionMs() = 0L
        override fun release() = Unit
    }

    private val bob = TestPlayer("Bob")
    private val dao get() = db.chatMessageDao()
    private val store = VoiceStore(java.nio.file.Files.createTempDirectory("voice").toFile())
    private val engine = Engine()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var autoplay = true
    private val player = VoicePlayer(
        engine, store, scope,
        markListened = { dao.markListened(it) },
        nextUnlistened = { peer, after -> dao.nextUnlistenedTrack(me.publicKeyB64, peer, after) },
        autoplay = { autoplay },
    )

    @After fun stop() { player.stop(); scope.cancel() }

    private suspend fun clip(from: String, to: String, id: String, ts: Long): VoiceTrack {
        store.write(id, ByteArray(100) { 1 })
        val row = dao.insert(
            ChatMessageEntity(type = "DM", fromPubKeyB64 = from, fromCallsign = "x", faction = "f", toPubKeyB64 = to, body = VoiceMarker.encode(id, 2_000, ByteArray(VoiceLimits.WAVEFORM_BARS)), timestamp = ts)
        )
        return dao.byId(row)!!.voiceTrack(me.publicKeyB64)!!
    }

    private fun waitFor(what: String, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + 5_000
        while (!cond()) {
            check(System.currentTimeMillis() < end) { "не дождались: $what (играло: ${engine.played})" }
            Thread.sleep(20)
        }
    }

    @Test fun clipsFromOnePeerPlayOneAfterAnotherUntilNothingIsLeft() = runBlocking {
        val a = clip(bob.key, me.publicKeyB64, "from-bob-aaaaaaa", 100)
        val b = clip(bob.key, me.publicKeyB64, "from-bob-bbbbbbb", 200)
        val c = clip(bob.key, me.publicKeyB64, "from-bob-ccccccc", 300)
        clip("OTHER", me.publicKeyB64, "other-zzzzzzzzz", 150) // чужая беседа в очередь не попадает
        player.toggle(a)
        waitFor("первое играет") { player.state.value.track?.rowId == a.rowId }
        engine.onCompleted()
        waitFor("второе пошло само") { player.state.value.track?.rowId == b.rowId }
        engine.onCompleted()
        waitFor("третье пошло само") { player.state.value.track?.rowId == c.rowId }
        engine.onCompleted()
        waitFor("тишина после последнего") { player.state.value.track == null }
        assertEquals(listOf("from-bob-aaaaaaa", "from-bob-bbbbbbb", "from-bob-ccccccc"), engine.played)
        listOf(a, b, c).forEach { assertEquals(MessageStatus.LISTENED, dao.byId(it.rowId)!!.status) }
        assertEquals("чужая беседа осталась непрослушанной", MessageStatus.NONE, dao.nextUnlistenedVoice(me.publicKeyB64, "OTHER", 0)!!.status)
    }

    @Test fun switchedOffOrOwnClipStopsAfterTheFirst() = runBlocking {
        val a = clip(bob.key, me.publicKeyB64, "from-bob-aaaaaaa", 100)
        clip(bob.key, me.publicKeyB64, "from-bob-bbbbbbb", 200)
        autoplay = false
        player.toggle(a)
        waitFor("первое играет") { player.state.value.track?.rowId == a.rowId }
        engine.onCompleted()
        waitFor("тишина") { player.state.value.track == null }
        Thread.sleep(200)
        assertNull("выключено — второе не пошло", player.state.value.track)
        assertEquals(1, engine.played.size)

        autoplay = true
        val own = clip(me.publicKeyB64, bob.key, "mine-to-bob-ccc", 300)
        player.toggle(own)
        waitFor("своё играет") { player.state.value.track?.rowId == own.rowId }
        engine.onCompleted()
        waitFor("тишина после своего") { player.state.value.track == null }
        Thread.sleep(200)
        assertEquals("после своего голосового следующее не включается", 2, engine.played.size)
    }
}
