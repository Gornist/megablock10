package com.megablok10.app.call

import com.megablok10.app.log.Mb10Log
import java.nio.ByteBuffer

/** Один кадр обработки: что нужно знать о нейросетевом шумодаве, не зная про JNI (в тестах — подмена). */
interface FrameDenoiser {
    /** Состояние на один поток микрофона; 0 — не создалось. */
    fun create(): Long
    fun destroy(handle: Long)
    /** Кадр [frames] отсчётов float (шкала int16) в прямом [buffer], на месте. Вероятность речи 0..1 или отрицательное число, если кадр не обработан. */
    fun process(handle: Long, buffer: ByteBuffer, frames: Int): Float
}

/**
 * JNI к RNNoise (src/main/cpp, BSD-3: rnnoise/COPYING). Библиотека не загрузилась (редкий ABI, сбой установки) — [available] = false, и звонок идёт со штатным шумоподавлением WebRTC
 * как раньше; об этом пишет CallMedia в журнал (`call.audio_denoise`).
 */
object RnNoiseNative : FrameDenoiser {
    val available: Boolean = try {
        System.loadLibrary("mb10rnnoise")
        true
    } catch (e: UnsatisfiedLinkError) {
        Mb10Log.warnEvent("RnNoise", "call.rnnoise_load_failed", "error" to e.javaClass.simpleName)
        false
    }

    external override fun create(): Long
    external override fun destroy(handle: Long)
    external override fun process(handle: Long, buffer: ByteBuffer, frames: Int): Float

    /** Самопроверка без микрофона: на сколько дБ сеть давит стационарный шум («кулер»). Больше 10 — работает. */
    external fun selfTestDb(): Float
}
