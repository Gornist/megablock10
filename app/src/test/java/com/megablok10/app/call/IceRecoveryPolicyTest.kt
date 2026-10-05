package com.megablok10.app.call

import com.megablok10.app.call.IceRecoveryPolicy.Action
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Политика восстановления звонка после потери связи: ждать, перезапускать ICE (только звонящий, до ответа), сдаться — а не висеть вечно. */
class IceRecoveryPolicyTest {
    private fun policy(caller: Boolean) = IceRecoveryPolicy(caller, graceMs = 4_000, retryMs = 8_000, giveUpMs = 45_000)

    @Test fun nothingHappensWhileConnected() {
        val p = policy(caller = true)
        p.onConnected()
        assertEquals(Action.NONE, p.tick(100_000))
        assertFalse(p.isLost())
    }

    @Test fun callerWaitsForGraceThenRestarts() {
        val p = policy(caller = true)
        p.onLost(now = 10_000)
        assertTrue(p.isLost())
        assertEquals(Action.NONE, p.tick(13_900))
        assertEquals(Action.RESTART, p.tick(14_000))
    }

    @Test fun callerRetriesNotMoreOftenThanRetryInterval() {
        val p = policy(caller = true)
        p.onLost(now = 0)
        assertEquals(Action.RESTART, p.tick(4_000))
        assertEquals(Action.NONE, p.tick(11_900))
        assertEquals(Action.RESTART, p.tick(12_000))
    }

    @Test fun restartIsRepeatedUntilPeerAnswersEvenIfOurIceLooksConnected() {
        // Живая проверка: звонящий сам снова CONNECTED, а OFFER ушёл в никуда — собеседник завис. Без ответа повторяем.
        val p = policy(caller = true)
        p.onLost(now = 0)
        assertEquals(Action.RESTART, p.tick(4_000))
        p.onConnected()
        assertEquals(Action.NONE, p.tick(11_900))
        assertEquals(Action.RESTART, p.tick(12_000))
        assertEquals(Action.RESTART, p.tick(20_000))
    }

    @Test fun answerStopsRetries() {
        val p = policy(caller = true)
        p.onLost(now = 0)
        assertEquals(Action.RESTART, p.tick(4_000))
        p.onRestartAnswered()
        p.onConnected()
        assertEquals(Action.NONE, p.tick(12_000))
        assertEquals(Action.NONE, p.tick(60_000))
    }

    @Test fun neverAnsweredRestartEventuallyGivesUp() {
        val p = policy(caller = true)
        p.onLost(now = 0)
        assertEquals(Action.RESTART, p.tick(4_000))
        p.onConnected()
        // срок считается от первого перезапуска (4 с): 4 + 45 = 49 с после потери
        assertTrue(p.tick(48_999) != Action.GIVE_UP)
        assertEquals(Action.GIVE_UP, p.tick(49_000))
    }

    @Test fun calleeNeverRestartsButGivesUp() {
        val p = policy(caller = false)
        p.onLost(now = 0)
        assertEquals(Action.NONE, p.tick(4_000))
        assertEquals(Action.NONE, p.tick(44_999))
        assertEquals(Action.GIVE_UP, p.tick(45_000))
    }

    @Test fun repeatedLossReportsDoNotPostponeDeadline() {
        val p = policy(caller = false)
        p.onLost(now = 0)
        p.onLost(now = 30_000)
        assertEquals(Action.GIVE_UP, p.tick(45_000))
    }

    @Test fun reconnectAfterAnsweredRestartResetsEverything() {
        val p = policy(caller = true)
        p.onLost(now = 0)
        assertEquals(Action.RESTART, p.tick(5_000))
        p.onRestartAnswered()
        p.onConnected()
        assertFalse(p.isLost())
        assertEquals(Action.NONE, p.tick(60_000))
        // новая потеря — отсчёт заново, с новым ожиданием
        p.onLost(now = 70_000)
        assertEquals(Action.NONE, p.tick(73_000))
        assertEquals(Action.RESTART, p.tick(74_000))
    }
}
