package com.megablok10.app.voice

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Выбор рекордера: шумодав — только если библиотека есть, выключатель не снят и состояние сети создаётся; иначе прежний MediaRecorder. */
class ClipRecorderFactoryTest {
    private class Marker(val name: String) : ClipRecorder {
        var started = 0
        var cancelled = 0
        override fun start(file: File): Boolean { started++; return true }
        override fun maxAmplitude(): Int = 7
        override fun stop(): Boolean = true
        override fun cancel() { cancelled++ }
    }

    private val denoised = Marker("denoised")
    private val plain = Marker("plain")

    private fun pick(available: Boolean, enabled: Boolean = true, usable: Boolean = true) =
        pickClipRecorder(available, enabled, { usable }, { denoised }, { plain })

    @Test fun libraryMissingUsesTheOldRecorder() = assertSame(plain, pick(available = false))

    @Test fun debugSwitchOffUsesTheOldRecorder() = assertSame(plain, pick(available = true, enabled = false))

    @Test fun networkStateNotCreatedUsesTheOldRecorder() = assertSame(plain, pick(available = true, usable = false))

    @Test fun everythingInPlaceUsesDenoise() = assertSame(denoised, pick(available = true))

    @Test fun engineIsNotProbedWithoutLibrary() {
        var probed = false
        pickClipRecorder(false, true, { probed = true; true }, { denoised }, { plain })
        assertFalse(probed)
    }

    @Test fun selectingRecorderChoosesOnEveryStartAndDelegates() {
        var useDenoise = true
        val selecting = SelectingClipRecorder(choose = { if (useDenoise) denoised else plain })
        assertEquals(0, selecting.maxAmplitude())
        assertTrue(selecting.start(File("a.m4a")))
        assertEquals(7, selecting.maxAmplitude())
        assertEquals(1, denoised.started)
        useDenoise = false
        assertTrue(selecting.start(File("b.m4a")))
        assertEquals("предыдущий закрыт", 1, denoised.cancelled)
        assertEquals(1, plain.started)
        assertTrue(selecting.stop())
    }

    private class Failing : ClipRecorder {
        override fun start(file: File): Boolean = false
        override fun maxAmplitude(): Int = 0
        override fun stop(): Boolean = false
        override fun cancel() {}
    }

    @Test fun failedStartFallsBackToTheOldRecorderAndKeepsUsingIt() {
        val failing = Failing()
        val selecting = SelectingClipRecorder(choose = { failing }, fallback = { plain })
        assertTrue(selecting.start(File("c.m4a")))
        assertEquals(1, plain.started)
        assertEquals("дальше работаем с запасным", 7, selecting.maxAmplitude())
        assertTrue(selecting.stop())
    }

    @Test fun failedStartWithoutFallbackStaysFalse() {
        assertFalse(SelectingClipRecorder(choose = { Failing() }).start(File("d.m4a")))
    }
}
