package com.megablok10.app.call

import com.megablok10.app.testing.FakeCallControls
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Экран гаснет у уха (proximity) на время набора и разговора и не мешает входящему звонку; блокировка не остаётся после сессии. */
class CallProximityGuardTest {
    private class FakeLock(override val supported: Boolean = true) : ProximityScreenLock {
        var held = false
        val history = mutableListOf<String>()
        override fun acquire() { held = true; history += "acquire" }
        override fun release() { held = false; history += "release" }
    }

    private fun state(phase: CallPhase) = CallUiState(phase = phase, callId = "c1")

    @Test fun whichPhasesWantTheScreenOff() {
        assertEquals(
            mapOf(CallPhase.IDLE to false, CallPhase.OUTGOING_RINGING to true, CallPhase.INCOMING_RINGING to false, CallPhase.IN_CALL to true),
            CallPhase.values().associateWith { wantsScreenOff(it) },
        )
    }

    @Test fun lockFollowsTheCall() = runTest {
        val calls = FakeCallControls()
        val lock = FakeLock()
        CallProximityGuard(calls, lock).start(this)
        advanceUntilIdle()
        assertFalse(lock.held)

        calls.state.value = state(CallPhase.INCOMING_RINGING)
        advanceUntilIdle()
        assertFalse("входящий звонок: экран нужен, чтобы нажать «Принять»", lock.held)

        calls.state.value = state(CallPhase.IN_CALL)
        advanceUntilIdle()
        assertTrue(lock.held)

        calls.state.value = state(CallPhase.IDLE)
        advanceUntilIdle()
        assertFalse(lock.held)
        coroutineContext[Job]!!.cancelChildren()
    }

    @Test fun lockIsReleasedWhenTheSessionStopsMidCall() = runTest {
        val calls = FakeCallControls(state(CallPhase.IN_CALL))
        val lock = FakeLock()
        val sessionJob = Job()
        val sessionScope = CoroutineScope(StandardTestDispatcher(testScheduler) + sessionJob)
        CallProximityGuard(calls, lock).start(sessionScope)
        advanceUntilIdle()
        assertTrue(lock.held)
        sessionJob.cancel()
        advanceUntilIdle()
        assertFalse("сброс персонажа посреди звонка не должен оставить блокировку", lock.held)
    }

    @Test fun unsupportedDeviceDoesNothing() = runTest {
        val lock = FakeLock(supported = false)
        CallProximityGuard(FakeCallControls(state(CallPhase.IN_CALL)), lock).start(this)
        advanceUntilIdle()
        assertTrue(lock.history.isEmpty())
    }

    private fun Job.cancelChildren() = children.forEach { it.cancel() }
}
