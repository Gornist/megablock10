package com.megablok10.app.voice

import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Проигрыватель голосовых: один играет, поверх запускается другое, «прослушано» в момент старта, автопроигрывание следующего, скорость, пауза от звонка. */
@OptIn(ExperimentalCoroutinesApi::class)
class VoicePlayerTest {
    @get:Rule val folder = TemporaryFolder()

    private class FakeEngine : ClipPlayer {
        override var onInterrupted: () -> Unit = {}
        override var onCompleted: () -> Unit = {}
        var playable = true
        var playing = false
        var position = 0L
        var currentSpeed = 1f
        val played = mutableListOf<String>()
        var released = 0
        override fun play(file: File, startMs: Long, speed: Float): Boolean {
            if (!playable) return false
            played += file.name; playing = true; position = startMs; currentSpeed = speed
            return true
        }
        override fun pause() { playing = false }
        override fun resume() { playing = true }
        override fun seekTo(ms: Long) { position = ms }
        override fun setSpeed(speed: Float) { currentSpeed = speed }
        override fun positionMs() = position
        override fun release() { playing = false; released++ }
    }

    private val engine = FakeEngine()
    private val store get() = VoiceStore(folder.root.resolve("voice"))
    private val listened = mutableListOf<Long>()
    private var autoplay = true
    private val queue = mutableListOf<VoiceTrack>() // что вернёт «следующее непрослушанное»

    private fun track(row: Long, incoming: Boolean = true, ts: Long = row * 10, peer: String = "peer") =
        VoiceTrack(row, "clip-%08d".format(row), 5_000, peer, incoming, ts).also { store.write(it.clipId, ByteArray(100) { 1 }) }

    private fun TestScope.player() = VoicePlayer(
        engine, store, this,
        markListened = { listened += it },
        nextUnlistened = { _, after -> queue.firstOrNull { it.timestamp > after } },
        autoplay = { autoplay },
    )

    @Test fun toggleStartsPausesAndResumes() = runTest {
        val p = player()
        val t = track(1)
        p.toggle(t); runCurrent()
        assertEquals(t, p.state.value.track)
        assertTrue(p.state.value.playing)
        p.toggle(t); runCurrent()
        assertFalse(p.state.value.playing); assertFalse(engine.playing)
        p.toggle(t); runCurrent()
        assertTrue(p.state.value.playing); assertTrue(engine.playing)
        p.stop()
    }

    @Test fun incomingIsMarkedListenedAtStartButOwnIsNot() = runTest {
        val p = player()
        p.toggle(track(1, incoming = true)); runCurrent()
        assertEquals(listOf(1L), listened)
        p.toggle(track(2, incoming = false)); runCurrent()
        assertEquals("своё голосовое «прослушанным» не помечается", listOf(1L), listened)
        p.stop()
    }

    @Test fun startingAnotherStopsTheFirst() = runTest {
        val p = player()
        p.toggle(track(1)); runCurrent()
        p.toggle(track(2)); runCurrent()
        assertEquals(2L, p.state.value.track?.rowId)
        assertEquals(listOf("clip-00000001.m4a", "clip-00000002.m4a"), engine.played)
        p.stop()
    }

    @Test fun positionFollowsTheEngine() = runTest {
        val p = player()
        p.toggle(track(1)); runCurrent()
        engine.position = 2_300
        advanceTimeBy(VoicePlayer.TICK_MS + 1); runCurrent()
        assertEquals(2_300, p.state.value.positionMs)
        p.stop()
    }

    @Test fun seekOnPlayingJumpsAndOnOtherStartsThere() = runTest {
        val p = player()
        val a = track(1); val b = track(2)
        p.toggle(a); runCurrent()
        p.seek(a, 0.5f)
        assertEquals(2_500, engine.position)
        p.seek(b, 0.2f); runCurrent()
        assertEquals(2L, p.state.value.track?.rowId)
        assertEquals(1_000, p.state.value.positionMs)
        p.stop()
    }

    @Test fun speedCyclesAndIsKeptForTheNextClip() = runTest {
        val p = player()
        p.toggle(track(1)); runCurrent()
        p.cycleSpeed(); assertEquals(1.5f, engine.currentSpeed)
        p.cycleSpeed(); assertEquals(2f, engine.currentSpeed)
        p.toggle(track(2)); runCurrent()
        assertEquals("скорость запоминается между сообщениями", 2f, engine.currentSpeed)
        p.cycleSpeed(); assertEquals(1f, p.state.value.speed)
        p.stop()
    }

    @Test fun finishedIncomingStartsTheNextUnlistenedWhenAutoplayIsOn() = runTest {
        val p = player()
        val first = track(1); val next = track(2)
        queue += next
        p.toggle(first); runCurrent()
        engine.onCompleted(); runCurrent()
        assertEquals(next, p.state.value.track)
        assertEquals(listOf(1L, 2L), listened)
        p.stop()
    }

    @Test fun autoplayOffOrOwnClipOrNothingNextJustStops() = runTest {
        val p = player()
        queue += track(2)
        autoplay = false
        p.toggle(track(1)); runCurrent(); engine.onCompleted(); runCurrent()
        assertNull(p.state.value.track)
        autoplay = true
        p.toggle(track(3, incoming = false)); runCurrent(); engine.onCompleted(); runCurrent()
        assertNull("после своего голосового следующее не включается", p.state.value.track)
        queue.clear()
        p.toggle(track(4)); runCurrent(); engine.onCompleted(); runCurrent()
        assertNull(p.state.value.track)
    }

    @Test fun interruptionPausesAndCallStops() = runTest {
        val p = player()
        val calls = MutableStateFlow(false)
        val watch = p.stopDuring(calls)
        p.toggle(track(1)); runCurrent()
        engine.onInterrupted()
        assertFalse(p.state.value.playing)
        p.toggle(track(1)); runCurrent()
        assertTrue(p.state.value.playing)
        calls.value = true; runCurrent()
        assertNull(p.state.value.track)
        watch.cancel()
    }

    @Test fun missingFileOrBrokenEngineDoesNotStartAndDoesNotMarkListened() = runTest {
        val p = player()
        p.toggle(VoiceTrack(9, "clip-00000009", 1_000, "peer", true, 90)); runCurrent()
        assertNull(p.state.value.track)
        engine.playable = false
        p.toggle(track(1)); runCurrent()
        assertNull(p.state.value.track)
        assertTrue(listened.isEmpty())
    }

    @Test fun speedLabelsAndCycle() {
        assertEquals(listOf("1×", "1,5×", "2×"), VoicePlayer.SPEEDS.map { VoicePlayer.speedLabel(it) })
        assertEquals(1.5f, VoicePlayer.nextSpeed(1f)); assertEquals(2f, VoicePlayer.nextSpeed(1.5f)); assertEquals(1f, VoicePlayer.nextSpeed(2f))
    }
}
