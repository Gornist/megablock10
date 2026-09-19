package com.megablok10.app.sound

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class BreachTonesTest {
    @Test
    fun `every cue renders audible, bounded, non-clipping audio of sane length`() {
        for (cue in BreachCue.values()) {
            val pcm = BreachTones.render(cue)
            val ms = pcm.size * 1000 / BreachTones.SAMPLE_RATE
            assertTrue("$cue: длина $ms мс", ms in 30..1000)
            val peak = pcm.maxOf { abs(it.toInt()) }
            assertTrue("$cue: тишина", peak > 1000)
            assertTrue("$cue: клиппинг", peak < Short.MAX_VALUE * 0.5)
        }
    }
}
