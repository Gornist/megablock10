package com.megablok10.app.voice

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Понижение частоты 48 → 16 кГц для голосового (микрофон пишется на 48 кГц ради RNNoise, а файл — 16 кГц). ФНЧ — FIR на окне Ханна (срез ≈6,8 кГц, 47 отсчётов), потом
 * каждый третий отсчёт: простое усреднение трёх отсчётов пропускало бы выше 8 кГц обратно в речевую полосу «зеркалом». Состояние (хвост фильтра) живёт между вызовами,
 * поэтому блоки любой длины склеиваются без щелчков; на входе, кратном трём, выходов ровно вход/3. Чистый Kotlin, без аллокаций в [process].
 */
class Resampler48To16 {
    private val ring = FloatArray(TAPS)
    private var pos = 0
    private var phase = 0

    /** Обрабатывает [count] отсчётов [input], пишет результат в [out] и возвращает, сколько записано (в [out] должно влезть (count + 2) / 3). */
    fun process(input: ShortArray, count: Int, out: ShortArray): Int {
        var written = 0
        for (i in 0 until count) {
            ring[pos] = input[i].toFloat()
            pos = (pos + 1) % TAPS
            if (++phase == FACTOR) {
                phase = 0
                out[written++] = filtered().roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }
        return written
    }

    /** Свёртка с последними [TAPS] отсчётами: самый новый — в `pos - 1`. */
    private fun filtered(): Float {
        var sum = 0f
        var idx = pos
        for (k in 0 until TAPS) {
            idx = if (idx == 0) TAPS - 1 else idx - 1
            sum += COEFFS[k] * ring[idx]
        }
        return sum
    }

    companion object {
        const val FACTOR = 3
        private const val TAPS = 47
        private const val CUTOFF_HZ = 6_800.0
        private const val RATE_HZ = 48_000.0

        /** Симметричный sinc с окном Ханна, нормированный на единичное усиление постоянной составляющей. */
        private val COEFFS: FloatArray = run {
            val mid = (TAPS - 1) / 2.0
            val fc = CUTOFF_HZ / RATE_HZ
            val raw = DoubleArray(TAPS) { k ->
                val x = k - mid
                val sinc = if (x == 0.0) 2 * fc else sin(2 * PI * fc * x) / (PI * x)
                sinc * (0.5 - 0.5 * cos(2 * PI * k / (TAPS - 1)))
            }
            val total = raw.sum()
            FloatArray(TAPS) { (raw[it] / total).toFloat() }
        }
    }
}
