package com.megablok10.app.voice

import com.megablok10.app.call.FrameDenoiser
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ядро записи: кадры по 480 отсчётов, пик после шумодава, средняя вероятность речи, откат на «как есть» после сбоев. Сеть подменена фейком (как в RnNoiseProcessorTest). */
class ClipPcmPipelineTest {
    /** Фейк: умножает кадр на [gain] и отдаёт вероятности из [probs] по кругу; отрицательная — кадр не обработан. */
    private class FakeEngine(var createOk: Boolean = true, var probs: List<Float> = listOf(0.5f), var gain: Float = 0.5f) : FrameDenoiser {
        var created = 0
        var destroyed = 0
        var processed = 0
        override fun create(): Long { created++; return if (createOk) created.toLong() else 0L }
        override fun destroy(handle: Long) { destroyed++ }
        override fun process(handle: Long, buffer: ByteBuffer, frames: Int): Float {
            val prob = probs[processed % probs.size]
            processed++
            if (prob >= 0f) {
                val f = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
                for (i in 0 until frames) f.put(i, f.get(i) * gain)
            }
            return prob
        }
    }

    private val chunks = mutableListOf<Int>()

    private fun pipeline(engine: FakeEngine) = ClipPcmPipeline(engine) { _, n -> chunks += n }

    private fun constant(value: Int, count: Int) = ShortArray(count) { value.toShort() }

    @Test fun framesGoThroughTheNetworkAndComeOutAs160Samples() {
        val engine = FakeEngine()
        val p = pipeline(engine)
        p.push(constant(1000, 1000), 1000)
        assertEquals(2, engine.processed)
        assertEquals(listOf(160, 160), chunks)
        p.push(constant(1000, 440), 440) // 40 + 440 = ещё один целый кадр
        assertEquals(3, engine.processed)
        assertEquals(3, chunks.size)
    }

    @Test fun peakIsMeasuredAfterDenoiseAndResets() {
        val p = pipeline(FakeEngine(gain = 0.5f))
        p.push(constant(-1000, 480), 480)
        assertEquals(500, p.takePeak())
        assertEquals(0, p.takePeak())
    }

    @Test fun peakIsCappedAtInt16() {
        val p = pipeline(FakeEngine(gain = 1f))
        p.push(constant(Short.MIN_VALUE.toInt(), 480), 480)
        assertEquals(32767, p.takePeak())
    }

    @Test fun silenceStaysSilent() {
        val p = pipeline(FakeEngine())
        p.push(ShortArray(960), 960)
        assertEquals(0, p.takePeak())
    }

    @Test fun speechProbabilityIsAveragedOverProcessedFrames() {
        val p = pipeline(FakeEngine(probs = listOf(0.2f, 0.4f)))
        p.push(constant(100, 960), 960)
        assertEquals(0.3, p.speechProbMean, 1e-6)
    }

    @Test fun threeBadFramesInARowSwitchToPassThroughAndFreeTheState() {
        val engine = FakeEngine(probs = listOf(-1f))
        val p = pipeline(engine)
        p.push(constant(1000, 480 * 3), 480 * 3)
        assertEquals(3, engine.processed)
        assertFalse(p.denoising)
        assertEquals(1, engine.destroyed)
        p.takePeak()
        p.push(constant(1000, 480), 480)
        assertEquals("после отката сеть не зовётся", 3, engine.processed)
        assertEquals("кадр идёт как есть", 1000, p.takePeak())
        assertEquals(4, chunks.size)
        p.release()
        assertEquals("состояние снимается один раз", 1, engine.destroyed)
    }

    @Test fun goodFrameResetsTheFailureCounter() {
        val engine = FakeEngine(probs = listOf(-1f, -1f, 0.5f))
        val p = pipeline(engine)
        p.push(constant(100, 480 * 6), 480 * 6)
        assertTrue(p.denoising)
        assertEquals(0, engine.destroyed)
    }

    @Test fun noNetworkStateMeansPassThroughFromTheStart() {
        val engine = FakeEngine(createOk = false)
        val p = pipeline(engine)
        assertFalse(p.denoising)
        p.push(constant(700, 480), 480)
        assertEquals(0, engine.processed)
        assertEquals(700, p.takePeak())
        assertEquals(0.0, p.speechProbMean, 0.0)
        p.release()
        assertEquals(0, engine.destroyed)
    }

    @Test fun releaseFreesTheStateOnce() {
        val engine = FakeEngine()
        val p = pipeline(engine)
        p.release()
        p.release()
        assertEquals(1, engine.destroyed)
    }
}
