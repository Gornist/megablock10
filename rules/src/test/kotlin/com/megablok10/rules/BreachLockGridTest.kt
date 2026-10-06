package com.megablok10.rules

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** Замок в генераторе (breach.md 2.1) и приманки (2.4): решаемость по построению, число и место приманок, старые вызовы без замка. */
class BreachLockGridTest {
    private fun deck(random: Random, vararg lens: Int) = lens.mapIndexed { i, len ->
        Daemon("d$i", "d$i", List(len) { BreachSymbols.ALPHABET.random(random) })
    }

    /** Колоды тира: один демон с цепочкой 2/3/4 (breach.md 6.1) и пара демонов 2+3 / 3+3 / 3+4 — как при большой RAM. */
    private fun decks(tier: Tier): List<IntArray> = listOf(
        intArrayOf(1 + tier.level),
        when (tier) {
            Tier.BASE -> intArrayOf(2, 3)
            Tier.HARD -> intArrayOf(3, 3)
            Tier.NIGHTMARE -> intArrayOf(3, 4)
        },
    )

    @Test
    fun `lock is solvable by construction on 1000 seeds per tier`() {
        for (tier in Tier.entries) {
            val params = BreachTierParams.forTier(tier)
            for (lens in decks(tier)) {
                for (seed in 1L..1000L) {
                    val random = Random(seed)
                    val daemons = deck(random, *lens)
                    val grid = generateGrid(params.gridSize, daemons, random, params, params.lockLength)
                    assertEquals("$tier seed $seed", params.lockLength, grid.lock.size)
                    val buffer = params.lockLength + daemons.sumOf { it.sequence.size }
                    val attempt = BreachAttemptState(grid, daemons, buffer)
                    val path = BreachAutoSolver.solve(attempt)
                    val solved = path.fold(attempt) { s, cell -> s.select(cell) }
                    assertEquals("$tier seed $seed ${lens.toList()}: решение не нашлось", daemons.size, solved.matchedDaemonIds.size)
                }
            }
        }
    }

    @Test
    fun `no lock keeps the grids of the old calls`() {
        for (tier in Tier.entries) {
            val params = BreachTierParams.forTier(tier)
            for (seed in 1L..50L) {
                val daemons = deck(Random(seed), 3)
                val old = generateGrid(params.gridSize, daemons, Random(seed + 1000), params)
                val zero = generateGrid(params.gridSize, daemons, Random(seed + 1000), params, lockLength = 0)
                assertEquals(old, zero)
                assertTrue(old.lock.isEmpty())
            }
        }
    }

    @Test
    fun `lock codes come from the alphabet and differ between seeds`() {
        val params = BreachTierParams.forTier(Tier.NIGHTMARE)
        val locks = (1L..60L).map { seed ->
            val daemons = deck(Random(seed), 4)
            generateGrid(params.gridSize, daemons, Random(seed), params, 3).lock
        }
        assertTrue(locks.all { l -> l.size == 3 && l.all { it in BreachSymbols.ALPHABET } })
        assertTrue("замок не должен быть один и тот же", locks.toSet().size > 10)
    }

    @Test
    fun `decoys per tier are within range and sit on cells with goal codes`() {
        for (tier in listOf(Tier.HARD, Tier.NIGHTMARE)) {
            val params = BreachTierParams.forTier(tier)
            val len = 1 + tier.level
            for (seed in 1L..500L) {
                val random = Random(seed)
                val daemons = deck(random, len)
                val grid = generateGrid(params.gridSize, daemons, random, params, params.lockLength)
                val dead = grid.trapCells.filter { grid.codeAt(it) == BreachSymbols.DEAD_MARKER }
                val decoys = grid.trapCells - dead.toSet()
                assertTrue("$tier seed $seed: приманок ${decoys.size}", decoys.size in params.corruptedCodesRange)
                assertTrue("$tier seed $seed: мёртвых ${dead.size}", dead.size in params.deadCellsRange)
                val goals = (grid.lock + daemons.flatMap { it.sequence }).toSet()
                val pathLen = grid.lock.size + len
                val goalCellsOffPath = grid.cells.flatten().count { it in goals } - pathLen
                // Если свободных клеток с кодом из целей хватает — приманки лежат только на них.
                if (goalCellsOffPath >= decoys.size) {
                    assertTrue("$tier seed $seed: приманка вне кодов целей", decoys.all { grid.codeAt(it) in goals })
                }
            }
        }
    }

    @Test
    fun `decoys of BASE are absent and old params without decoys are unchanged`() {
        val params = BreachTierParams.forTier(Tier.BASE)
        for (seed in 1L..200L) {
            val random = Random(seed)
            val grid = generateGrid(params.gridSize, deck(random, 2), random, params, params.lockLength)
            assertTrue(grid.trapCells.isEmpty())
        }
    }
}
