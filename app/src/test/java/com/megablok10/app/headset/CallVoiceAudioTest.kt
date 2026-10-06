package com.megablok10.app.headset

import com.megablok10.app.call.CallAudioHooks
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Пересэмплер, очередь и подмена звука звонка звуком очков (без WebRTC: буферы и ключевые точки как у JavaAudioDeviceModule). */
class CallVoiceAudioTest {
    @After fun cleanHooks() {
        CallAudioHooks.mic = null
        CallAudioHooks.playback = null
    }

    // ---- пересэмплер ----

    @Test fun sameRateKeepsTheSamples() {
        val x = ShortArray(10) { it.toShort() }
        assertEquals(x.toList(), PcmResampler(16_000, 16_000).process(x).toList())
    }

    @Test fun outputLengthFollowsTheRateRatio() {
        val r = PcmResampler(44_100, 48_000)
        var out = 0
        repeat(100) { out += r.process(ShortArray(441)).size }
        assertEquals(48_000 * 1.0, out.toDouble(), 5.0) // 100 кусков по 10 мс = 1 с
    }

    @Test fun constantSignalStaysConstantAcrossChunkBorders() {
        val r = PcmResampler(48_000, 44_100)
        val out = (1..20).flatMap { r.process(ShortArray(480) { 1000 }).toList() }.drop(1)
        assertTrue("сигнал не должен щёлкать на стыках", out.all { abs(it - 1000) <= 1 })
    }

    @Test fun chunkedAndWholeProcessingGiveTheSameSamples() {
        val x = ShortArray(4410) { (10_000 * sin(2 * PI * 440 * it / 44_100)).toInt().toShort() }
        val whole = PcmResampler(44_100, 16_000).process(x)
        val r = PcmResampler(44_100, 16_000)
        val parts = (0 until 10).flatMap { r.process(x.copyOfRange(it * 441, it * 441 + 441)).toList() }
        val n = minOf(whole.size, parts.size)
        assertTrue("кусками и целиком — те же отсчёты с точностью до округления", (0 until n).all { abs(whole[it] - parts[it]) <= 1 })
        assertTrue(n > 100)
    }

    @Test fun sineKeepsItsAmplitudeWhenResampled() {
        val x = ShortArray(44_100) { (10_000 * sin(2 * PI * 300 * it / 44_100)).toInt().toShort() }
        val y = PcmResampler(44_100, 48_000).process(x)
        assertEquals(10_000.0, y.maxOf { it.toInt() }.toDouble(), 150.0)
    }

    @Test fun emptyInputGivesEmptyOutput() {
        assertEquals(0, PcmResampler(44_100, 48_000).process(ShortArray(0)).size)
    }

    // ---- очередь ----

    @Test fun queueReadsWhatWasPushedInOrder() {
        val q = PcmQueue(10)
        q.push(shortArrayOf(1, 2, 3))
        val out = ShortArray(5)
        assertEquals(3, q.read(out))
        assertEquals(listOf<Short>(1, 2, 3), out.take(3))
        assertEquals(0, q.available())
    }

    @Test fun queueDropsTheOldestWhenFull() {
        val q = PcmQueue(4)
        q.push(shortArrayOf(1, 2, 3))
        assertEquals(2, q.push(shortArrayOf(4, 5, 6)))
        val out = ShortArray(4)
        assertEquals(4, q.read(out))
        assertEquals(listOf<Short>(3, 4, 5, 6), out.toList())
    }

    @Test fun queueKeepsTheTailOfAnOversizedChunk() {
        val q = PcmQueue(3)
        assertEquals(2, q.push(shortArrayOf(1, 2, 3, 4, 5)))
        val out = ShortArray(3)
        q.read(out)
        assertEquals(listOf<Short>(3, 4, 5), out.toList())
    }

    // ---- подмена микрофона ----

    private fun micBuffer(frames: Int, channels: Int = 1): ByteBuffer = ByteBuffer.allocateDirect(frames * channels * 2).order(ByteOrder.BIG_ENDIAN)

    private fun ByteBuffer.shortAt(frame: Int, channel: Int = 0, channels: Int = 1): Int {
        val i = (frame * channels + channel) * 2
        return ((get(i + 1).toInt() shl 8) or (get(i).toInt() and 0xFF)).toShort().toInt()
    }

    @Test fun micFramesAreWrittenLittleEndianResampledToTheCallRate() {
        val audio = CallVoiceAudio(speaker = { true })
        audio.route(true)
        val warm = micBuffer(160)
        audio.fill(warm, 320, 16_000, 1) // первый буфер сообщает частоту записи
        audio.feedMic(ShortArray(441 * 4) { 2000 })
        val buf = micBuffer(160)
        audio.fill(buf, 320, 16_000, 1)
        assertTrue("есть звук очков", (10 until 150).all { abs(buf.shortAt(it) - 2000) <= 1 })
    }

    @Test fun underrunIsSilenceAndCounted() {
        val audio = CallVoiceAudio(speaker = { true })
        audio.route(true)
        val buf = micBuffer(160).also { b -> for (i in 0 until 320) b.put(i, 0x55) }
        audio.fill(buf, 320, 16_000, 1)
        assertTrue((0 until 160).all { buf.shortAt(it) == 0 })
        assertEquals(1L, audio.micUnderruns)
    }

    @Test fun muteSilencesTheMicEvenWithGlassesAudio() {
        val audio = CallVoiceAudio(speaker = { true })
        audio.route(true)
        audio.fill(micBuffer(160), 320, 16_000, 1)
        audio.feedMic(ShortArray(441 * 4) { 2000 })
        audio.setMuted(true)
        val buf = micBuffer(160)
        audio.fill(buf, 320, 16_000, 1)
        assertTrue((0 until 160).all { buf.shortAt(it) == 0 })
    }

    @Test fun stereoBuffersGetTheSameSampleInBothChannels() {
        val audio = CallVoiceAudio(speaker = { true })
        audio.route(true)
        audio.fill(micBuffer(160, 2), 640, 16_000, 2)
        audio.feedMic(ShortArray(441 * 4) { 1500 })
        val buf = micBuffer(160, 2)
        audio.fill(buf, 640, 16_000, 2)
        assertEquals(buf.shortAt(50, 0, 2), buf.shortAt(50, 1, 2))
        assertTrue(abs(buf.shortAt(50, 0, 2) - 1500) <= 1)
    }

    @Test fun inactiveRouteLeavesTheMicBufferUntouched() {
        val audio = CallVoiceAudio(speaker = { true })
        val buf = micBuffer(160).also { b -> for (i in 0 until 320) b.put(i, 0x33) }
        audio.fill(buf, 320, 16_000, 1)
        assertTrue((0 until 320).all { buf.get(it).toInt() == 0x33 })
    }

    // ---- звук собеседника и динамик ----

    private fun pcmBytes(samples: Int, value: Int): ByteArray = ByteArray(samples * 2).also { b ->
        for (i in 0 until samples) {
            b[i * 2] = value.toByte()
            b[i * 2 + 1] = (value shr 8).toByte()
        }
    }

    @Test fun playbackIsResampledAndCutIntoTwentyMillisecondChunks() {
        val audio = CallVoiceAudio(speaker = { true })
        val chunks = mutableListOf<ShortArray>()
        audio.route(true) { chunks += it }
        repeat(10) { audio.onSamples(pcmBytes(480, 3000), 48_000, 1) } // 100 мс на 48 кГц
        assertTrue("за 100 мс — около пяти кусков по 20 мс", chunks.size in 4..5)
        assertTrue(chunks.all { it.size == HEADSET_VOICE_CHUNK })
        assertTrue(chunks.drop(1).all { c -> c.all { abs(it - 3000) <= 1 } })
    }

    @Test fun stereoPlaybackIsMixedDownToMono() {
        val audio = CallVoiceAudio(speaker = { true })
        val chunks = mutableListOf<ShortArray>()
        audio.route(true) { chunks += it }
        val stereo = ByteArray(480 * 2 * 2)
        for (f in 0 until 480) {
            stereo[f * 4] = 1000.toByte(); stereo[f * 4 + 1] = (1000 shr 8).toByte()
            stereo[f * 4 + 2] = 3000.toByte(); stereo[f * 4 + 3] = (3000 shr 8).toByte()
        }
        repeat(10) { audio.onSamples(stereo, 48_000, 2) }
        assertTrue(chunks.drop(1).all { c -> c.all { abs(it - 2000) <= 1 } })
    }

    @Test fun speakerIsSilencedOnRouteAndRestoredOnRelease() {
        val volumes = mutableListOf<Float>()
        val audio = CallVoiceAudio(speaker = { volumes += it; true })
        audio.route(true)
        audio.route(false)
        assertEquals(listOf(0f, 1f), volumes)
        assertNull(CallAudioHooks.mic)
        assertNull(CallAudioHooks.playback)
    }

    @Test fun speakerIsRetriedWhileTheTrackIsNotThereYetButNotTooOften() {
        var ready = false
        val volumes = mutableListOf<Float>()
        var now = 1_000L
        val audio = CallVoiceAudio(speaker = { v -> volumes += v; ready }, now = { now })
        audio.route(true)
        audio.onSamples(pcmBytes(480, 1), 48_000, 1)
        now += 100
        audio.onSamples(pcmBytes(480, 1), 48_000, 1)
        now += 600
        ready = true
        audio.onSamples(pcmBytes(480, 1), 48_000, 1)
        audio.onSamples(pcmBytes(480, 1), 48_000, 1)
        assertEquals("попытки: при включении и раз в 500 мс, после успеха — больше нет", listOf(0f, 0f, 0f), volumes)
    }

    @Test fun routeInstallsTheHooksOnlyWhileActive() {
        val audio = CallVoiceAudio(speaker = { true })
        assertNull(CallAudioHooks.mic)
        audio.route(true)
        assertTrue(CallAudioHooks.mic === audio && CallAudioHooks.playback === audio)
        audio.route(false)
        assertNull(CallAudioHooks.mic)
    }
}
