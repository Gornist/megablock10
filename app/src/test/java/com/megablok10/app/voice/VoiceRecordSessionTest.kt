package com.megablok10.app.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** Запись как в Telegram: удержание, смахнуть влево — отмена, вверх — закрепить, короткая не уходит, предел длины. */
class VoiceRecordSessionTest {
    @get:Rule val folder = TemporaryFolder()

    private class FakeRecorder(var startOk: Boolean = true, var stopOk: Boolean = true, var bytes: Int = 4_000) : ClipRecorder {
        var started: File? = null
        var cancelled = 0
        var amplitude = 8_000
        override fun start(file: File): Boolean {
            started = file.takeIf { startOk }
            return startOk
        }
        override fun maxAmplitude() = amplitude
        override fun stop(): Boolean {
            started?.takeIf { stopOk }?.writeBytes(ByteArray(bytes) { 1 })
            return stopOk
        }
        override fun cancel() { cancelled++ }
    }

    private var clock = 10_000L
    private val recorder = FakeRecorder()
    private var counter = 0
    private val session = VoiceRecordSession(recorder, { "clip-%08d".format(++counter) to folder.root.resolve("clip$counter.m4a") }, { clock }, thresholdPx = 100f)

    private fun hold(ms: Long) {
        assertTrue(session.start())
        var spent = 0L
        while (spent < ms) { clock += 100; spent += 100; session.tick() }
    }

    @Test fun gesturesAreClassifiedByTheDominantDirection() {
        val t = 100f
        assertEquals(VoiceGesture.HOLD, VoiceRecordSession.classify(-50f, -50f, t))
        assertEquals(VoiceGesture.CANCEL, VoiceRecordSession.classify(-150f, -20f, t))
        assertEquals(VoiceGesture.LOCK, VoiceRecordSession.classify(-20f, -150f, t))
        assertEquals("по диагонали побеждает большее смещение", VoiceGesture.LOCK, VoiceRecordSession.classify(-120f, -160f, t))
        assertEquals(VoiceGesture.CANCEL, VoiceRecordSession.classify(-160f, -120f, t))
        assertEquals("вправо и вниз — просто удержание", VoiceGesture.HOLD, VoiceRecordSession.classify(300f, 300f, t))
    }

    @Test fun holdAndReleaseSendsTheClipWithDurationAndWaveform() {
        hold(3_000)
        val result = session.release() as VoiceResult.Send
        assertEquals(3_000, result.clip.durationMs)
        assertEquals(VoiceLimits.WAVEFORM_BARS, result.clip.waveform.size)
        assertTrue(result.clip.file.isFile)
        assertEquals("clip-00000001", result.clip.id)
        assertFalse(session.isRecording)
    }

    @Test fun swipeLeftCancelsAndDeletesTheFile() {
        hold(3_000)
        session.onDrag(-150f, 0f)
        assertTrue(session.state.willCancel)
        assertEquals(VoiceResult.Cancelled, session.release())
        assertEquals(1, recorder.cancelled)
        assertFalse(folder.root.resolve("clip1.m4a").exists())
    }

    @Test fun movingTheFingerBackUndoesTheCancel() {
        hold(3_000)
        session.onDrag(-150f, 0f)
        session.onDrag(-20f, 0f)
        assertFalse(session.state.willCancel)
        assertTrue(session.release() is VoiceResult.Send)
    }

    @Test fun swipeUpLocksSoReleaseDoesNothingAndButtonsFinish() {
        hold(3_000)
        session.onDrag(0f, -150f)
        assertTrue(session.state.locked)
        assertNull("закреплённую запись отпускание не трогает", session.release())
        assertTrue(session.isRecording)
        session.onDrag(-300f, 0f) // после закрепления жесты больше не действуют
        assertFalse(session.state.willCancel)
        hold(0)
        assertTrue(session.sendLocked() is VoiceResult.Send)
    }

    @Test fun lockedRecordingCanBeCancelledByTheButton() {
        hold(2_000)
        session.onDrag(0f, -150f)
        assertEquals(VoiceResult.Cancelled, session.cancel())
        assertFalse(session.isRecording)
    }

    @Test fun tooShortRecordingIsDropped() {
        hold(500)
        assertEquals(VoiceResult.TooShort, session.release())
        assertFalse(folder.root.resolve("clip1.m4a").exists())
    }

    @Test fun recorderFailureToStartOrStopIsReported() {
        recorder.startOk = false
        assertFalse(session.start())
        recorder.startOk = true
        hold(2_000)
        recorder.stopOk = false
        assertEquals(VoiceResult.Failed, session.release())
    }

    @Test fun limitStopsAndSendsByItself() {
        assertTrue(session.start())
        var result: VoiceResult? = null
        var guard = 0
        while (result == null && guard++ < 1_000) { clock += 1_000; result = session.tick() }
        val send = result as VoiceResult.Send
        assertEquals(VoiceLimits.MAX_DURATION_MS, send.clip.durationMs)
        assertFalse(session.isRecording)
    }

    @Test fun oversizeFileIsRefused() {
        recorder.bytes = VoiceLimits.MAX_AUDIO_BYTES + 1
        hold(2_000)
        assertEquals(VoiceResult.Failed, session.release())
    }

    @Test fun waveformFollowsTheLoudness() {
        val quiet = VoiceWaveform.bars(List(100) { 0 })
        val loud = VoiceWaveform.bars(List(100) { 32_767 })
        assertTrue(quiet.all { VoiceWaveform.height(it) < 0.1f })
        assertTrue(loud.all { VoiceWaveform.height(it) > 0.99f })
        val mixed = VoiceWaveform.bars(List(64) { if (it < 32) 0 else 32_767 })
        assertTrue(VoiceWaveform.height(mixed[0]) < VoiceWaveform.height(mixed[63]))
        assertEquals(VoiceLimits.WAVEFORM_BARS, VoiceWaveform.bars(emptyList()).size)
    }
}
