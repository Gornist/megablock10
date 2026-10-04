package com.megablok10.app.breach

import com.megablok10.rules.generateGrid
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class BreachRunTest {
    private val daemons = MockBreach.daemons
    private val params = BreachTierParams.forTier(Tier.BASE)
    private val grid = generateGrid(params.gridSize, daemons, Random(1L), params)

    private fun run(timerSec: Int = 60, bufferSize: Int = 6) = BreachRun(BreachAttemptState(grid, daemons, bufferSize), timerSec)

    @Test fun freshRunStartsWithFullTimerAndNoResult() {
        val run = run(timerSec = 45)

        assertEquals(45, run.secondsLeft)
        assertNull(run.result)
        assertFalse(run.isFinished)
        assertTrue(run.isTicking)
        assertTrue(run.selectable.isNotEmpty())
    }

    @Test fun tickCountsDownAndTheTimerStopsAtZero() {
        var run = run(timerSec = 2)

        run = run.tick()
        assertEquals(1, run.secondsLeft)
        assertTrue(run.isTicking)
        run = run.tick()
        assertEquals(0, run.secondsLeft)
        assertFalse(run.isTicking)
    }

    @Test fun tapAddsTheCellAndReportsTrapAndMatchLikeTheOldScreen() {
        val start = run()
        val first = start.attempt.selectableCells().first()

        val tap = start.tap(first)

        assertEquals(listOf(first), tap.run.attempt.selected)
        assertEquals(first in grid.trapCells, tap.hitTrap)
        assertEquals(tap.run.attempt.matchedDaemonIds.size > start.attempt.matchedDaemonIds.size, tap.matched)
    }

    @Test fun autoSolverPathMatchesEveryDaemonAndFillingTheBufferStopsTheTimer() {
        var run = run(bufferSize = 6)
        val path = BreachAutoSolver.solve(run.attempt)
        var matchedTaps = 0
        for (cell in path) {
            val tap = run.tap(cell)
            if (tap.matched) matchedTaps++
            run = tap.run
        }

        assertTrue("совпадения замечены на тапах", matchedTaps > 0)
        assertEquals(daemons.map { it.id }.toSet(), run.attempt.matchedDaemonIds)
    }

    @Test fun fullBufferEndsTheTimerLoopAndLeavesNothingToTap() {
        var run = run(bufferSize = 2)
        repeat(2) { run = run.tap(run.attempt.selectableCells().first()).run }

        assertTrue(run.attempt.isFull)
        assertFalse(run.isTicking)
        assertTrue(run.selectable.isEmpty())
    }

    @Test fun resolveFixesTheResultFromTheCurrentAttemptOnlyOnce() {
        var run = run()
        run = run.tap(run.attempt.selectableCells().first()).run

        val resolved = run.resolve()

        val result = resolved.result!!
        assertEquals(daemons, result.allDaemons)
        assertEquals(run.attempt.matchedDaemonIds, result.matchedIds)
        assertTrue(resolved.isFinished)
        assertSame("второй resolve ничего не меняет", resolved, resolved.resolve())
        assertTrue("после итога тапать нельзя", resolved.selectable.isEmpty())
        assertFalse(resolved.isTicking)
    }

    @Test fun emptyAttemptResolvesToFail() {
        assertEquals(BreachOutcome.FAIL, run().resolve().result!!.outcome)
    }

    @Test fun lowTimeAndWarningWindowsMatchTheTimerBlinkAndBeep() {
        val run = run(timerSec = 60)

        assertFalse(run.copy(secondsLeft = 11).isLowTime)
        assertTrue(run.copy(secondsLeft = 10).isLowTime)
        assertTrue(run.copy(secondsLeft = 1).isLowTime)
        assertFalse(run.copy(secondsLeft = 0).isLowTime)
        assertFalse("после итога не мигает", run.copy(secondsLeft = 5).resolve().isLowTime)
        assertFalse(run.copy(secondsLeft = 6).isWarning)
        assertTrue(run.copy(secondsLeft = 5).isWarning)
        assertTrue(run.copy(secondsLeft = 1).isWarning)
        assertFalse(run.copy(secondsLeft = 0).isWarning)
    }

    @Test fun iceTimeEventsAppearOnlyInLongTimers() {
        val long = run(timerSec = 60)
        assertEquals(IceEvent.HALF_TIME, long.copy(secondsLeft = 30).timeEvent)
        assertEquals(IceEvent.LOW_TIME, long.copy(secondsLeft = 10).timeEvent)
        assertNull(long.copy(secondsLeft = 29).timeEvent)

        val short = run(timerSec = 20)
        assertNull(short.copy(secondsLeft = 10).timeEvent)
    }

    @Test fun whenHalfTimeCoincidesWithTenSecondsTheLastReplyWins() {
        assertEquals(IceEvent.LOW_TIME, run(timerSec = 21).copy(secondsLeft = 10).timeEvent)
    }
}
