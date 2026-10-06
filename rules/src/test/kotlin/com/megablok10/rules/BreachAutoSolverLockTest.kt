package com.megablok10.rules

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Солвер знает замок и порядок breach.md 2.2: сперва вскрывает замок, потом добычу. */
class BreachAutoSolverLockTest {
    private val lock = listOf("1C", "55")
    private val extract = Daemon("extract", "extract", listOf("BD", "E9"), Tier.BASE, DaemonEffect.EXTRACT_SHARD)

    /** Замок и цепочка лежат на одном пути: 1C,55 в столбце 0, затем BD в строке 1 и E9 в столбце 1. Рядом — ловушка-приманка. */
    private val grid = BreachGrid(
        size = 3,
        cells = listOf(listOf("1C", "BD", "FF"), listOf("55", "BD", "FF"), listOf("FF", "E9", "FF")),
        trapCells = setOf(0 to 1),
        lock = lock,
    )

    @Test
    fun `solver opens the lock first and then takes the loot`() {
        val start = BreachAttemptState(grid, listOf(extract), bufferSize = 4)
        val path = BreachAutoSolver.solve(start)
        assertEquals(listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1), path)
        val solved = path.fold(start) { s, cell -> s.select(cell) }
        assertTrue(solved.lockOpened)
        assertEquals(setOf("extract"), solved.matchedDaemonIds)
    }

    @Test
    fun `solver with a buffer one short of lock plus loot cannot take the loot`() {
        val start = BreachAttemptState(grid, listOf(extract), bufferSize = 3)
        val solved = BreachAutoSolver.solve(start).fold(start) { s, cell -> s.select(cell) }
        assertEquals(emptySet<String>(), solved.matchedDaemonIds)
    }

    @Test
    fun `solver without a lock needs no lock to take the loot`() {
        val plain = grid.copy(lock = emptyList(), trapCells = emptySet())
        val start = BreachAttemptState(plain, listOf(extract), bufferSize = 4)
        val solved = BreachAutoSolver.solve(start).fold(start) { s, cell -> s.select(cell) }
        assertEquals(setOf("extract"), solved.matchedDaemonIds)
        assertFalse(solved.lockOpened)
    }
}
