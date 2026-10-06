package com.megablok10.app.call

import java.nio.ByteBuffer

/**
 * Точки подмены звука звонка (WebRTC `JavaAudioDeviceModule`): через них очки Pico (пакет headset, срез 3) становятся микрофоном и динамиком
 * звонка. Пока ничего не назначено, колбэки WebRTC ничего не делают, и звонок идёт как раньше.
 *
 * Оба колбэка вызываются из аудиопотоков WebRTC — реализации обязаны быть быстрыми и без блокировок.
 */
object CallAudioHooks {
    /** Подмена микрофона: [fill] перезаписывает только что снятый с микрофона телефона буфер звуком очков. */
    interface Mic {
        /** [buffer] — PCM 16 бит little-endian, [bytes] байт, [channels] каналов с частотой [rate]; писать по абсолютным индексам. */
        fun fill(buffer: ByteBuffer, bytes: Int, rate: Int, channels: Int)
    }

    /** Отвод звука собеседника: то, что играет динамик телефона (PCM 16 бит little-endian, [channels] каналов, [rate] Гц). */
    interface Playback {
        fun onSamples(data: ByteArray, rate: Int, channels: Int)
    }

    @Volatile var mic: Mic? = null
    @Volatile var playback: Playback? = null
}
