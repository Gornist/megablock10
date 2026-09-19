package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.random.Random

class BreachAutoSolverTest {
    @Test
    fun `solves every tier with the starter daemon`() {
        for (tier in Tier.values()) {
            val params = BreachTierParams.forTier(tier)
            repeat(30) { seed ->
                val daemons = MockBreach.daemons
                val grid = generateGrid(params.gridSize, daemons, Random(seed.toLong()), params)
                val start = BreachAttemptState(grid, daemons, 6)
                val path = BreachAutoSolver.solve(start)
                var state = start
                for (cell in path) state = state.select(cell)
                assertEquals("tier=$tier seed=$seed", daemons.map { it.id }.toSet(), state.matchedDaemonIds)
            }
        }
    }
}
