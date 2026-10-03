package com.megablok10.app.presence

import com.megablok10.app.testing.ManualNsdScheduler
import org.junit.Assert.assertEquals
import org.junit.Test

/** Операции NSD по одной (B3): снять незавершённую регистрацию нельзя по построению — ровно то, что теряло устройство в сети. */
class NsdSlotTest {
    private val calls = mutableListOf<String>()
    private val scheduler = ManualNsdScheduler()
    private val slot = NsdSlot(object : NsdSlot.Ops<Int> {
        override fun start(value: Int, token: Int) { calls += "start($value)#$token" }
        override fun stop(token: Int) { calls += "stop#$token" }
    }, scheduler, opTimeoutMs = 10_000, retryMs = 5_000)

    @Test fun startsOnceAndWaitsForTheAnswer() {
        slot.want(47100)
        slot.want(47100)
        assertEquals(listOf("start(47100)#1"), calls)
        slot.onStarted(1)
        assertEquals(NsdSlot.Phase.UP, slot.phase)
    }

    @Test fun restartDuringRegistrationWaitsForItToFinish() {
        // Журнал CI 25.09: nsd.start и через 60 мс nsd.refresh — раньше это снимало регистрацию, не дождавшись ответа.
        slot.want(47100)
        slot.restart()
        slot.restart()
        assertEquals("пока ответа нет — ничего не трогаем", listOf("start(47100)#1"), calls)
        slot.onStarted(1)
        slot.onStopped(2)
        slot.onStarted(3)
        assertEquals(listOf("start(47100)#1", "stop#2", "start(47100)#3"), calls)
        assertEquals(NsdSlot.Phase.UP, slot.phase)
    }

    @Test fun stopWhileStartingStopsOnlyAfterStartAnswered() {
        slot.want(47100)
        slot.want(null)
        assertEquals(listOf("start(47100)#1"), calls)
        slot.onStarted(1)
        assertEquals(listOf("start(47100)#1", "stop#2"), calls)
        slot.onStopped(2)
        assertEquals(NsdSlot.Phase.IDLE, slot.phase)
    }

    @Test fun newValueReplacesTheOldOneInOrder() {
        slot.want(1); slot.onStarted(1)
        slot.want(2)
        slot.onStopped(2)
        assertEquals(listOf("start(1)#1", "stop#2", "start(2)#3"), calls)
    }

    @Test fun failedStartIsRetriedLater() {
        slot.want(47100)
        slot.onStartFailed(1)
        assertEquals(NsdSlot.Phase.IDLE, slot.phase)
        scheduler.advance(4_999)
        assertEquals(1, calls.size)
        scheduler.advance(1)
        assertEquals(listOf("start(47100)#1", "start(47100)#2"), calls)
    }

    @Test fun lostAnswerTimesOutAndStartsAgain() {
        slot.want(47100)
        scheduler.advance(10_000)
        assertEquals("без ответа: снять на всякий случай и начать заново", listOf("start(47100)#1", "stop#1", "start(47100)#2"), calls)
        slot.onStarted(1) // запоздалый ответ на потерянную операцию — не в счёт
        assertEquals(NsdSlot.Phase.STARTING, slot.phase)
        slot.onStarted(2)
        assertEquals(NsdSlot.Phase.UP, slot.phase)
    }

    @Test fun answeredOperationCancelsItsTimeout() {
        slot.want(47100)
        slot.onStarted(1)
        scheduler.advance(60_000)
        assertEquals(listOf("start(47100)#1"), calls)
    }

    @Test fun restartWithNothingWantedDoesNothing() {
        slot.restart()
        assertEquals(emptyList<String>(), calls)
    }
}
