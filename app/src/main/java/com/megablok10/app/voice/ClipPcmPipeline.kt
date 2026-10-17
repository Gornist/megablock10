package com.megablok10.app.voice

import com.megablok10.app.call.FrameDenoiser
import com.megablok10.app.log.Mb10Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.roundToInt

private const val TAG = "VoiceRecorder"

/**
 * Ядро записи голосового без Android: PCM 48 кГц моно (int16) → кадры по 480 отсчётов → RNNoise → [Resampler48To16] → блоки по 160 отсчётов 16 кГц в [sink] (оттуда их берёт
 * кодек). Так же ведёт себя [com.megablok10.app.call.RnNoiseProcessor]: [MAX_FAILS] плохих кадров подряд — состояние сети снимается, дальше кадры идут как есть (запись не рвётся,
 * только без шумодава); не создалось состояние сети — то же с самого начала. Неполный хвост кадра (<10 мс) на остановке теряется. Звать [push] и [release] из одного потока;
 * [takePeak] — из любого (его зовёт экран за громкостью), счётчики для журнала читать после остановки потока записи.
 */
class ClipPcmPipeline(private val engine: FrameDenoiser, private val sink: (ShortArray, Int) -> Unit) {
    private var handle = engine.create()
    private val frame = ShortArray(FRAME)
    private var filled = 0
    private val buffer = ByteBuffer.allocateDirect(FRAME * Float.SIZE_BYTES).order(ByteOrder.nativeOrder())
    private val floats = buffer.asFloatBuffer()
    private val resampler = Resampler48To16()
    private val out = ShortArray(FRAME / Resampler48To16.FACTOR + 1)
    private val peak = AtomicInteger(0)
    private var fails = 0
    private var probSum = 0.0
    private var probCount = 0

    /** Работает ли шумодав сейчас. */
    val denoising: Boolean get() = handle != 0L

    /** Средняя вероятность речи по обработанным кадрам; 0, если шумодав не обработал ни одного. */
    val speechProbMean: Double get() = if (probCount == 0) 0.0 else probSum / probCount

    /** Принять [count] отсчётов 48 кГц из [input]. */
    fun push(input: ShortArray, count: Int) {
        for (i in 0 until count) {
            frame[filled++] = input[i]
            if (filled == FRAME) {
                filled = 0
                processFrame()
            }
        }
    }

    /** Пик абсолютного значения (после шумодава) с прошлого вызова, 0..32767. */
    fun takePeak(): Int = peak.getAndSet(0)

    /** Освободить состояние сети; повторный вызов безвреден. */
    fun release() {
        if (handle != 0L) engine.destroy(handle)
        handle = 0L
    }

    private fun processFrame() {
        if (handle != 0L) denoiseFrame()
        var framePeak = 0
        for (v in frame) {
            val a = if (v < 0) -v.toInt() else v.toInt()
            if (a > framePeak) framePeak = a
        }
        peak.accumulateAndGet(minOf(framePeak, Short.MAX_VALUE.toInt())) { cur, new -> maxOf(cur, new) }
        val n = resampler.process(frame, FRAME, out)
        if (n > 0) sink(out, n)
    }

    private fun denoiseFrame() {
        floats.clear()
        for (v in frame) floats.put(v.toFloat())
        val prob = engine.process(handle, buffer, FRAME)
        if (prob >= 0f) {
            fails = 0
            probSum += prob
            probCount++
            floats.clear()
            for (i in 0 until FRAME) frame[i] = floats.get().roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        } else if (++fails >= MAX_FAILS) {
            Mb10Log.warnEvent(TAG, "voice.rnnoise", "state" to "failed")
            release()
        }
    }

    companion object {
        const val SAMPLE_RATE = 48_000
        const val FRAME = 480
        const val MAX_FAILS = 3
    }
}
