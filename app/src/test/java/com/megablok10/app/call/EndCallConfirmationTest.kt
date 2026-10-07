package com.megablok10.app.call

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** «Завершить» во время разговора — со второго нажатия: одиночное касание щекой звонок не сбрасывает. */
class EndCallConfirmationTest {
    @Test fun firstTapOnlyArmsSecondTapEnds() {
        val c = EndCallConfirmation(windowMs = 3_000)
        assertFalse(c.onTap(now = 10_000))
        assertTrue(c.isArmed(10_500))
        assertTrue(c.onTap(now = 11_000))
    }

    @Test fun lateSecondTapJustArmsAgain() {
        val c = EndCallConfirmation(windowMs = 3_000)
        assertFalse(c.onTap(10_000))
        assertFalse("окно истекло", c.isArmed(13_000))
        assertFalse(c.onTap(13_000))
        assertTrue(c.onTap(14_000))
    }

    @Test fun afterEndingTheNextTapStartsOver() {
        val c = EndCallConfirmation(windowMs = 3_000)
        c.onTap(1_000)
        assertTrue(c.onTap(1_500))
        assertFalse(c.isArmed(1_600))
        assertFalse(c.onTap(1_700))
    }
}
