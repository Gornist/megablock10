package com.megablok10.rules

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Числа тиров Взлома 2.0 (breach.md, раздел 3) и функция буфера (2.3): правка числа без правки этого теста — красный CI. */
class BreachTierParamsTest {
    private fun p(tier: Tier) = BreachTierParams.forTier(tier)

    @Test
    fun `timers lock slack and decoys per tier`() {
        assertEquals(listOf(45, 90, 150), Tier.entries.map { p(it).timerSec })
        assertEquals(listOf(1, 2, 3), Tier.entries.map { p(it).lockLength })
        assertEquals(listOf(2, 1, 0), Tier.entries.map { p(it).bufferSlack })
        assertEquals(listOf(0..0, 1..2, 3..4), Tier.entries.map { p(it).corruptedCodesRange })
        assertEquals(listOf(0..0, 2..3, 5..6), Tier.entries.map { p(it).deadCellsRange })
    }

    @Test
    fun `cipher lock of a shard keeps the old timers`() {
        assertEquals(listOf(45, 60, 75), Tier.entries.map { p(it).cipherTimerSec })
    }

    @Test
    fun `fail penalty is only on hard and nightmare`() {
        assertEquals(0, p(Tier.BASE).failPenaltyMinutes)
        listOf(Tier.HARD, Tier.NIGHTMARE).forEach {
            val x = p(it)
            assertEquals(1, x.failPenaltyLockStep)
            assertEquals(1, x.failPenaltyTrapStep)
            assertEquals(2, x.failPenaltyMaxSteps)
            assertEquals(10, x.failPenaltyMinutes)
        }
    }

    @Test
    fun `old style params keep the old behaviour by defaults`() {
        val old = BreachParams(gridSize = 5, timerSec = 45, deadCellsRange = 0..0, corruptedCodesRange = 0..0)
        assertEquals(0, old.lockLength)
        assertEquals(0, old.bufferSlack)
        assertEquals(45, old.cipherTimerSec)
        assertEquals(0, old.failPenaltyMinutes)
    }

    @Test
    fun `buffer is the least of ram and lock plus daemons plus slack`() {
        // BASE: замок 1, демон 2, запас 2 → 5 из RAM 6.
        assertEquals(5, BreachTierParams.bufferSize(ram = 6, lockLength = 1, daemonsLen = 2, tier = Tier.BASE))
        // BASE: замок 1, демон 3, запас 2 → 6, RAM 6 режет ровно.
        assertEquals(6, BreachTierParams.bufferSize(6, 1, 3, Tier.BASE))
        // HARD: замок 2, демон 3, запас 1 → 6, RAM 6.
        assertEquals(6, BreachTierParams.bufferSize(6, 2, 3, Tier.HARD))
        // HARD: замок 2, демоны 3+3, запас 1 → 9, RAM 8 режет до 8.
        assertEquals(8, BreachTierParams.bufferSize(8, 2, 6, Tier.HARD))
        // NIGHTMARE: запаса нет — ровно замок + демон.
        assertEquals(7, BreachTierParams.bufferSize(10, 3, 4, Tier.NIGHTMARE))
        assertEquals(6, BreachTierParams.bufferSize(6, 3, 4, Tier.NIGHTMARE))
    }

    @Test
    fun `deck fits ram only when lock plus daemons fit`() {
        assertTrue(BreachTierParams.fitsRam(ram = 6, lockLength = 3, daemonsLen = 3))
        assertFalse(BreachTierParams.fitsRam(ram = 6, lockLength = 3, daemonsLen = 4))
        // NIGHTMARE с RAM 6: один демон из 3 кодов влезает, два — нет (breach.md 2.3).
        assertTrue(BreachTierParams.fitsRam(6, p(Tier.NIGHTMARE).lockLength, 3))
        assertFalse(BreachTierParams.fitsRam(6, p(Tier.NIGHTMARE).lockLength, 3 + 3))
    }
}
