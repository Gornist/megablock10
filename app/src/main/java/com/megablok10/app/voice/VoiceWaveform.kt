package com.megablok10.app.voice

/**
 * Волна голосового сообщения: [VoiceLimits.WAVEFORM_BARS] столбиков 0..255, считаются при записи из замеров громкости (`MediaRecorder.getMaxAmplitude`, 0..32767,
 * раз в ~100 мс) и едут вместе со звуком (байты в [VoiceWireMessage.waveform]) — пузырь рисуется без чтения файла.
 */
object VoiceWaveform {
    private const val MAX_AMPLITUDE = 32_767.0
    private const val MIN_BAR = 12

    /** [samples] делятся на [count] равных долей, столбик — максимум доли; тишина и пустая запись дают ровную низкую полосу. */
    fun bars(samples: List<Int>, count: Int = VoiceLimits.WAVEFORM_BARS): ByteArray {
        val bars = ByteArray(count)
        for (i in 0 until count) {
            val from = samples.size * i / count
            val to = maxOf(from + 1, samples.size * (i + 1) / count).coerceAtMost(samples.size)
            val peak = if (from < to) samples.subList(from, to).max() else 0
            bars[i] = level(peak).toByte()
        }
        return bars
    }

    /** Громкость → высота столбика: корень выравнивает тихую речь и громкий крик, чтобы волна не была плоской линией с редкими пиками. */
    private fun level(amplitude: Int): Int {
        val unit = (amplitude.coerceIn(0, MAX_AMPLITUDE.toInt()) / MAX_AMPLITUDE).let { Math.sqrt(it) }
        return (MIN_BAR + unit * (255 - MIN_BAR)).toInt().coerceIn(MIN_BAR, 255)
    }

    /** Высота столбика 0..1 для рисования. */
    fun height(bar: Byte): Float = (bar.toInt() and 0xFF) / 255f
}
