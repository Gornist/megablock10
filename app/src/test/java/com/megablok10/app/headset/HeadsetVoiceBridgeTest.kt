package com.megablok10.app.headset

import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.testing.FakeCallControls
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Голос звонка в очках: порядок `voice` → `voice_ready`, маршрут звука, возврат на телефон по тишине, сбросу, концу звонка и обрыву. */
@OptIn(ExperimentalCoroutinesApi::class)
class HeadsetVoiceBridgeTest {
    private class FakeAudio : VoiceAudioPort {
        val routes = mutableListOf<Boolean>()
        val mic = mutableListOf<ShortArray>()
        val muted = mutableListOf<Boolean>()
        var sendPlayback: (ShortArray) -> Unit = {}
        override fun route(active: Boolean, sendPlayback: (ShortArray) -> Unit) {
            routes += active
            this.sendPlayback = sendPlayback
        }
        override fun feedMic(pcm: ShortArray) { mic += pcm }
        override fun setMuted(muted: Boolean) { this.muted += muted }
    }

    private class Env(enabled: Boolean = true, phase: CallPhase = CallPhase.IDLE) {
        val calls = FakeCallControls(CallUiState(phase = phase))
        val audio = FakeAudio()
        val sent = mutableListOf<HeadsetOut>()
        val binary = mutableListOf<ByteArray>()
        var now = 1_000L
        var enabled = enabled
        val bridge = HeadsetVoiceBridge(calls, audio, { this.enabled }, { now })
        fun observe(scope: TestScope) = bridge.observe(scope.backgroundScope, { sent += it; true }, { binary += it; true })
        fun phase(p: CallPhase) { calls.state.value = calls.state.value.copy(phase = p) }
        fun mic(seq: Long, samples: Int = 4) = bridge.onBinary(HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_MIC, seq, ShortArray(samples) { it.toShort() }))
        val voiceFrames get() = sent.filterIsInstance<HeadsetOut.Voice>()
    }

    @Test fun armsWhenTheCallGoesInCallAndWaitsForGlassesReady() = runTest {
        val e = Env().also { it.observe(this) }
        runCurrent()
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        assertEquals(listOf(HeadsetOut.Voice(true)), e.voiceFrames)
        assertEquals(HeadsetVoiceBridge.State.ARMED, e.bridge.state)
        assertTrue("маршрут до voice_ready не включается", e.audio.routes.isEmpty())
    }

    @Test fun doesNothingWhileTheVoiceSwitchIsOff() = runTest {
        val e = Env(enabled = false).also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        assertTrue(e.voiceFrames.isEmpty())
        assertEquals(HeadsetVoiceBridge.State.OFF, e.bridge.state)
    }

    @Test fun voiceReadyActivatesTheRouteAndMicFramesAreFedToTheCall() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        assertTrue(e.bridge.handle(HeadsetCommand.VoiceReady(true)))
        assertEquals(listOf(true), e.audio.routes)
        e.mic(0)
        e.mic(1)
        assertEquals(2, e.audio.mic.size)
        assertEquals(listOf<Short>(0, 1, 2, 3), e.audio.mic.first().toList())
    }

    @Test fun playbackIsSentToGlassesAsNumberedBinaryFrames() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        e.audio.sendPlayback(ShortArray(HEADSET_VOICE_CHUNK) { 5 })
        e.audio.sendPlayback(ShortArray(HEADSET_VOICE_CHUNK) { 6 })
        val frames = e.binary.map { HeadsetVoiceCodec.decode(it)!! }
        assertEquals(listOf(0L, 1L), frames.map { it.seq })
        assertTrue(frames.all { it.type == HeadsetVoiceCodec.TYPE_PLAYBACK && it.pcm.size == HEADSET_VOICE_CHUNK })
    }

    @Test fun micFramesBeforeReadyAndPlaybackTypedFramesAreIgnored() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.mic(0)
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        e.bridge.onBinary(HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_PLAYBACK, 1, ShortArray(4)))
        e.bridge.onBinary(byteArrayOf(1, 2))
        assertTrue(e.audio.mic.isEmpty())
    }

    @Test fun silenceFromTheGlassesReturnsTheSoundToThePhone() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        e.mic(0)
        e.now += HeadsetVoiceBridge.SILENCE_MS - 1
        e.bridge.tick()
        assertEquals(HeadsetVoiceBridge.State.ACTIVE, e.bridge.state)
        e.now += 2
        e.bridge.tick()
        assertEquals(HeadsetVoiceBridge.State.FALLBACK, e.bridge.state)
        assertEquals(listOf(true, false), e.audio.routes)
        assertEquals(HeadsetOut.Voice(false), e.voiceFrames.last())
    }

    @Test fun noReadyAnswerGivesUpWithoutTouchingTheRoute() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.now += HeadsetVoiceBridge.READY_MS + 1
        e.bridge.tick()
        assertEquals(HeadsetVoiceBridge.State.FALLBACK, e.bridge.state)
        assertTrue(e.audio.routes.isEmpty())
        assertEquals(HeadsetOut.Voice(false), e.voiceFrames.last())
    }

    @Test fun glassesTakenOffReturnTheSoundAndTheCallDoesNotRearmInTheSameCall() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        e.bridge.handle(HeadsetCommand.VoiceReady(false))
        assertEquals(listOf(true, false), e.audio.routes)
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        assertEquals("в этом звонке голос в очки не возвращается", listOf(true, false), e.audio.routes)
    }

    @Test fun endOfCallReleasesTheRouteAndTheNextCallArmsAgain() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        e.phase(CallPhase.IDLE)
        runCurrent()
        assertEquals(listOf(true, false), e.audio.routes)
        assertEquals(HeadsetVoiceBridge.State.OFF, e.bridge.state)
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        assertEquals(HeadsetVoiceBridge.State.ARMED, e.bridge.state)
    }

    @Test fun lostLinkReleasesTheRoute() = runTest {
        val e = Env().also { it.observe(this) }
        e.phase(CallPhase.IN_CALL)
        runCurrent()
        e.bridge.handle(HeadsetCommand.VoiceReady(true))
        e.bridge.stop()
        assertEquals(listOf(true, false), e.audio.routes)
        assertEquals(HeadsetVoiceBridge.State.OFF, e.bridge.state)
    }

    @Test fun muteIsForwardedToTheAudioRoute() = runTest {
        val e = Env().also { it.observe(this) }
        runCurrent()
        e.calls.state.value = e.calls.state.value.copy(muted = true)
        runCurrent()
        e.calls.state.value = e.calls.state.value.copy(muted = false)
        runCurrent()
        assertEquals(listOf(false, true, false), e.audio.muted)
    }

    @Test fun foreignCommandsAreNotHandled() = runTest {
        val e = Env().also { it.observe(this) }
        assertEquals(false, e.bridge.handle(HeadsetCommand.Accept))
    }
}
