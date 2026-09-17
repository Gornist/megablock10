package com.megablok10.app.breach

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class ContainerEddiesTest {

    @Test
    fun `BASE tier rolls stay within 1 to 3`() = assertRollsWithin(Tier.BASE, 1..3)

    @Test
    fun `HARD tier rolls stay within 4 to 6`() = assertRollsWithin(Tier.HARD, 4..6)

    @Test
    fun `NIGHTMARE tier rolls stay within 7 to 10`() = assertRollsWithin(Tier.NIGHTMARE, 7..10)

    private fun assertRollsWithin(tier: Tier, expected: IntRange) {
        repeat(200) { seed ->
            val roll = ContainerEddies.roll(tier, Random(seed.toLong()))
            assertTrue("тир $tier выдал $roll, ожидался диапазон $expected (seed=$seed)", roll in expected.first.toLong()..expected.last.toLong())
        }
    }
}
