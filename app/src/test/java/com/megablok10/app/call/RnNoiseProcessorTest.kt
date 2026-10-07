package com.megablok10.app.call

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Обработчик кадров микрофона: работает только на 48 кГц и целых 10-мс кадрах, при сбоях тихо откатывается на штатное (кадр не трогается). Сама сеть проверена на хосте (cpp/check/check.sh) и на эмуляторе (e2e rnnoise). */
class RnNoiseProcessorTest {
    private class FakeEngine(var createOk: Boolean = true, var result: Float = 0.5f) : FrameDenoiser {
        var created = 0
        var destroyed = 0
        var processed = 0
        override fun create(): Long { created++; return if (createOk) created.toLong() else 0L }
        override fun destroy(handle: Long) { destroyed++ }
        override fun process(handle: Long, buffer: ByteBuffer, frames: Int): Float { processed++; return result }
    }

    private val engine = FakeEngine()
    private val processor = RnNoiseProcessor(engine)
    private val buffer = ByteBuffer.allocateDirect(RnNoiseProcessor.FRAME * 4).order(ByteOrder.nativeOrder())

    @After fun release() = processor.release()

    @Test fun fullBandFramesGoToTheNetwork() {
        processor.initialize(48_000, 1)
        assertTrue(processor.active)
        processor.process(3, 480, buffer)
        processor.process(3, 480, buffer)
        assertEquals(2, engine.processed)
    }

    @Test fun otherRatesAndPartialFramesAreLeftAlone() {
        processor.initialize(16_000, 1)
        assertFalse("тракт не 48 кГц — обход без падения", processor.active)
        processor.process(1, 160, buffer)
        processor.reset(48_000)
        assertTrue(processor.active)
        processor.process(3, 160, buffer) // не целый кадр RNNoise
        assertEquals(0, engine.processed)
    }

    @Test fun resetRebuildsTheStateAndFreesTheOldOne() {
        processor.initialize(48_000, 1)
        processor.reset(48_000)
        assertEquals(2, engine.created)
        assertEquals(1, engine.destroyed)
    }

    @Test fun failedInitMeansPassThrough() {
        engine.createOk = false
        processor.initialize(48_000, 1)
        assertFalse(processor.active)
        processor.process(3, 480, buffer)
        assertEquals(0, engine.processed)
    }

    @Test fun repeatedBadFramesSwitchTheNetworkOff() {
        processor.initialize(48_000, 1)
        engine.result = -1f
        repeat(RnNoiseProcessor.MAX_FAILS) { processor.process(3, 480, buffer) }
        assertFalse("после нескольких плохих кадров подряд откат на штатное", processor.active)
        assertEquals(1, engine.destroyed)
        processor.process(3, 480, buffer)
        assertEquals(RnNoiseProcessor.MAX_FAILS, engine.processed)
    }

    @Test fun oneBadFrameAmongGoodOnesDoesNotSwitchOff() {
        processor.initialize(48_000, 1)
        engine.result = -1f
        processor.process(3, 480, buffer)
        engine.result = 0.9f
        repeat(10) { processor.process(3, 480, buffer) }
        assertTrue(processor.active)
    }

    @Test fun releaseIsIdempotent() {
        processor.initialize(48_000, 1)
        processor.release()
        processor.release()
        assertEquals(1, engine.destroyed)
    }

    @Test fun denoiseSwitchParsesTheDebugSpec() {
        CallDenoise.apply("rnnoise=0")
        assertFalse(CallDenoise.enabled)
        CallDenoise.apply("junk,rnnoise=1")
        assertTrue(CallDenoise.enabled)
        CallDenoise.apply("")
        assertTrue("пусто — по умолчанию включено", CallDenoise.enabled)
    }
}
