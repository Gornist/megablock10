package com.megablok10.app.voice

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Понижение 48 → 16 кГц: длина, тишина, сохранение речевой полосы и подавление зеркала выше 8 кГц. */
class Resampler48To16Test {
    private fun sine(freqHz: Double, amplitude: Double, samples: Int) = ShortArray(samples) { (amplitude * sin(2 * PI * freqHz * it / 48_000.0)).toInt().toShort() }

    private fun run(input: ShortArray, chunk: Int = input.size): ShortArray {
        val r = Resampler48To16()
        val out = ShortArray(input.size / 3 + 2)
        var total = 0
        var from = 0
        while (from < input.size) {
            val n = minOf(chunk, input.size - from)
            val part = input.copyOfRange(from, from + n)
            val tmp = ShortArray(n / 3 + 2)
            val w = r.process(part, n, tmp)
            tmp.copyInto(out, total, 0, w)
            total += w
            from += n
        }
        return out.copyOf(total)
    }

    @Test fun outputLengthIsInputOverThree() {
        assertEquals(160, run(ShortArray(480)).size)
        assertEquals(1600, run(ShortArray(4800), chunk = 480).size)
    }

    @Test fun oddChunkSizesGiveTheSameStream() {
        val input = sine(1_000.0, 10_000.0, 4_800)
        val whole = run(input)
        val pieces = run(input, chunk = 101)
        assertEquals(whole.size, pieces.size)
        assertTrue("блоки любой длины склеиваются без швов", whole.indices.all { whole[it] == pieces[it] })
    }

    @Test fun silenceStaysSilence() {
        assertTrue(run(ShortArray(2_400)).all { it.toInt() == 0 })
    }

    @Test fun speechBandKeepsAmplitude() {
        val out = run(sine(1_000.0, 10_000.0, 9_600))
        val settled = out.drop(100)
        val peak = settled.maxOf { abs(it.toInt()) }
        assertTrue("пик $peak", peak in 9_000..11_000)
    }

    @Test fun aboveEightKilohertzDoesNotFoldBack() {
        val out = run(sine(12_000.0, 10_000.0, 9_600))
        val peak = out.drop(100).maxOf { abs(it.toInt()) }
        assertTrue("зеркало 12 кГц → 4 кГц осталось: $peak", peak < 1_000)
    }
}
