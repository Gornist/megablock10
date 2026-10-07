package com.megablok10.app.call

import com.megablok10.app.log.Mb10Log
import java.nio.ByteBuffer
import org.webrtc.ExternalAudioProcessingFactory

private const val TAG = "RnNoise"

/**
 * Нейросетевой шумодав (RNNoise) после штатной обработки WebRTC на микрофоне звонка: [ExternalAudioProcessingFactory.setCapturePostProcessing] отдаёт каждые 10 мс
 * моно-буфер (канал 0) float в шкале int16 — ровно кадр RNNoise при 48 кГц (480 отсчётов); обработка на месте, без копий и аллокаций. Тракт не 48 кГц (на практике бывает
 * только у экзотики) — кадр идёт как есть, в журнал один раз (`call.rnnoise_bypass`): звонок не страдает, шум остаётся на совести штатного NS. Сбой init/кадра — тоже откат на
 * штатное (после [MAX_FAILS] подряд плохих кадров состояние снимается), в журнале `call.rnnoise state=…`.
 */
class RnNoiseProcessor(private val engine: FrameDenoiser = RnNoiseNative) : ExternalAudioProcessingFactory.AudioProcessing {
    private var handle = 0L
    private var rate = 0
    private var fails = 0

    /** Работает ли шумодав прямо сейчас (для журнала и тестов). */
    @get:Synchronized val active: Boolean get() = handle != 0L

    @Synchronized override fun initialize(sampleRateHz: Int, numChannels: Int) = rebuild(sampleRateHz)

    @Synchronized override fun reset(newRate: Int) = rebuild(newRate)

    @Synchronized override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (handle == 0L || numFrames != FRAME) return
        if (engine.process(handle, buffer, numFrames) >= 0f) {
            fails = 0
        } else if (++fails >= MAX_FAILS) {
            Mb10Log.warnEvent(TAG, "call.rnnoise", "state" to "failed")
            release()
        }
    }

    @Synchronized fun release() {
        if (handle != 0L) engine.destroy(handle)
        handle = 0L
    }

    private fun rebuild(newRate: Int) {
        release()
        rate = newRate
        fails = 0
        if (newRate != SAMPLE_RATE) {
            Mb10Log.event(TAG, "call.rnnoise_bypass", "rate" to newRate)
            return
        }
        handle = engine.create()
        Mb10Log.event(TAG, "call.rnnoise", "state" to if (handle != 0L) "on" else "init_failed", "rate" to rate)
    }

    companion object {
        const val SAMPLE_RATE = 48_000
        const val FRAME = 480
        const val MAX_FAILS = 3
    }
}
