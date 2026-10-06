package com.megablok10.app.headset

import com.megablok10.app.call.CallAudioHooks
import com.megablok10.app.call.CallMedia
import com.megablok10.app.log.Mb10Log
import java.nio.ByteBuffer

/** Звук звонка для очков: что подставить вместо микрофона телефона и куда отдать звук собеседника. Реализация — [CallVoiceAudio]; в тестах — фейк. */
interface VoiceAudioPort {
    /** Включает или выключает маршрут. [sendPlayback] получает звук собеседника кусками по [HEADSET_VOICE_CHUNK] отсчётов на [HEADSET_VOICE_RATE]. */
    fun route(active: Boolean, sendPlayback: (ShortArray) -> Unit = {})

    /** Звук микрофона очков (моно, [HEADSET_VOICE_RATE]). */
    fun feedMic(pcm: ShortArray)

    /** Свой микрофон выключен: собеседнику уходит тишина, даже если очки шлют звук. */
    fun setMuted(muted: Boolean)
}

/**
 * Подмена звука звонка WebRTC звуком очков (срез 3). Пока маршрут включён: микрофон звонка = очередь из кадров очков (пересэмплирована под
 * частоту WebRTC), звук собеседника уходит очкам, динамик телефона тихий ([speaker] = громкость AudioTrack). Нехватка звука очков — тишина
 * (провал сети не должен ронять запись), избыток — выбрасывается старое.
 *
 * [fill] и [onSamples] вызываются из аудиопотоков WebRTC и не блокируются; [feedMic] — из сетевого потока.
 */
class CallVoiceAudio(
    private val speaker: (Float) -> Boolean = CallMedia::setSpeakerVolume,
    private val now: () -> Long = System::currentTimeMillis,
) : VoiceAudioPort, CallAudioHooks.Mic, CallAudioHooks.Playback {
    @Volatile private var active = false
    @Volatile private var muted = false
    @Volatile private var sendPlayback: (ShortArray) -> Unit = {}

    private val micQueue = PcmQueue(MIC_QUEUE_SAMPLES)
    @Volatile private var micRate = 0
    private var micResampler: PcmResampler? = null
    private var micScratch = ShortArray(0)

    private var playbackRate = 0
    private var playbackResampler: PcmResampler? = null
    private var acc = ShortArray(HEADSET_VOICE_CHUNK * 4)
    private var accLen = 0
    private var speakerQuiet = false
    private var speakerTriedAt = 0L

    @Volatile var micDropped = 0L; private set
    @Volatile var micUnderruns = 0L; private set

    override fun route(active: Boolean, sendPlayback: (ShortArray) -> Unit) {
        if (active == this.active) return
        if (active) {
            this.sendPlayback = sendPlayback
            micQueue.clear()
            micResampler = null
            playbackResampler = null
            accLen = 0
            speakerQuiet = false
            speakerTriedAt = 0L
            micDropped = 0
            micUnderruns = 0
            CallAudioHooks.mic = this
            CallAudioHooks.playback = this
            this.active = true
            quietSpeaker()
        } else {
            this.active = false
            CallAudioHooks.mic = null
            CallAudioHooks.playback = null
            this.sendPlayback = {}
            if (speakerQuiet) speaker(1f)
            speakerQuiet = false
        }
    }

    override fun setMuted(muted: Boolean) {
        this.muted = muted
    }

    override fun feedMic(pcm: ShortArray) {
        val rate = micRate
        if (!active || rate == 0) return // частота записи WebRTC неизвестна, пока не пришёл первый буфер
        val resampler = micResampler?.takeIf { it.toRate == rate } ?: PcmResampler(HEADSET_VOICE_RATE, rate).also { micResampler = it }
        micDropped += micQueue.push(resampler.process(pcm))
    }

    override fun fill(buffer: ByteBuffer, bytes: Int, rate: Int, channels: Int) {
        micRate = rate
        if (!active) return
        val frames = bytes / (BYTES_PER_SAMPLE * channels)
        if (micScratch.size < frames) micScratch = ShortArray(frames)
        val read = if (muted) 0 else micQueue.read(micScratch, frames)
        if (!muted && read < frames) micUnderruns++
        for (f in 0 until frames) {
            val s = if (muted || f >= read) 0 else micScratch[f].toInt()
            for (c in 0 until channels) {
                val i = (f * channels + c) * BYTES_PER_SAMPLE
                buffer.put(i, s.toByte())
                buffer.put(i + 1, (s shr BYTE_BITS).toByte())
            }
        }
    }

    override fun onSamples(data: ByteArray, rate: Int, channels: Int) {
        if (!active) return
        if (!speakerQuiet) quietSpeakerThrottled()
        val frames = data.size / (BYTES_PER_SAMPLE * channels)
        val mono = ShortArray(frames) { f ->
            var sum = 0
            for (c in 0 until channels) {
                val i = (f * channels + c) * BYTES_PER_SAMPLE
                sum += ((data[i + 1].toInt() shl BYTE_BITS) or (data[i].toInt() and BYTE_MASK)).toShort().toInt()
            }
            (sum / channels).toShort()
        }
        if (rate != playbackRate || playbackResampler == null) {
            playbackRate = rate
            playbackResampler = PcmResampler(rate, HEADSET_VOICE_RATE)
        }
        val out = playbackResampler?.process(mono) ?: return
        if (accLen + out.size > acc.size) acc = acc.copyOf(accLen + out.size + HEADSET_VOICE_CHUNK)
        out.copyInto(acc, accLen)
        accLen += out.size
        while (accLen >= HEADSET_VOICE_CHUNK) {
            sendPlayback(acc.copyOf(HEADSET_VOICE_CHUNK))
            acc.copyInto(acc, 0, HEADSET_VOICE_CHUNK, accLen)
            accLen -= HEADSET_VOICE_CHUNK
        }
    }

    private fun quietSpeaker() {
        speakerQuiet = speaker(0f)
        if (!speakerQuiet) Mb10Log.event(TAG, "headset.voice_speaker_pending")
    }

    /** Трек динамика мог ещё не создаться к включению маршрута: повторяем, но не чаще раза в [SPEAKER_RETRY_MS]. */
    private fun quietSpeakerThrottled() {
        val t = now()
        if (t - speakerTriedAt < SPEAKER_RETRY_MS) return
        speakerTriedAt = t
        quietSpeaker()
    }

    private companion object {
        const val TAG = "Headset"
        const val BYTES_PER_SAMPLE = 2
        const val BYTE_BITS = 8
        const val BYTE_MASK = 0xFF
        const val MIC_QUEUE_SAMPLES = 48_000 / 5 // 200 мс на максимальной частоте WebRTC
        const val SPEAKER_RETRY_MS = 500L
    }
}
