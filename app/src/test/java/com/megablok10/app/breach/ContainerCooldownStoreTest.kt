package com.megablok10.app.breach

import com.megablok10.app.DebugConfig
import com.megablok10.app.data.ContainerBreachEntity
import com.megablok10.app.testing.RoomTest
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Кулдаун контейнера на настоящей Room. Store берёт время из System.currentTimeMillis (часов не принимает), поэтому отметки
 * ставятся относительно «сейчас» с запасом в минуту, а граница порога — ровно по значению: время идёт только вперёд, так что
 * «прошёл ровно порог» всегда даёт 0.
 */
@RunWith(RobolectricTestRunner::class)
class ContainerCooldownStoreTest : RoomTest() {
    private val dao get() = db.containerBreachDao()
    private val store get() = ContainerCooldownStore(dao)
    private val cooldownMs = MockBreach.containerCooldownMinutes * 60_000L
    private val minute = 60_000L

    @After fun resetClockSpeed() { DebugConfig.clockSpeed = 1.0 }

    private suspend fun rewardedAgo(containerId: String, agoMs: Long) = dao.upsert(ContainerBreachEntity(containerId, System.currentTimeMillis() - agoMs))

    @Test fun aContainerNeverRewardedHereHasNoCooldown() = runBlocking {
        assertEquals(0L, store.remainingCooldownMs("c1"))
        assertNull(dao.lastRewardedAt("c1"))
    }

    @Test fun rightAfterMarkingTheWholeCooldownRemains() = runBlocking {
        val before = System.currentTimeMillis()
        store.markRewarded("c1")
        val after = System.currentTimeMillis()

        val stamped = dao.lastRewardedAt("c1")!!
        assertTrue(stamped in before..after)
        val remaining = store.remainingCooldownMs("c1")
        assertTrue("осталось $remaining из $cooldownMs", remaining in (cooldownMs - minute)..cooldownMs)
    }

    @Test fun beforeTheThresholdTheRemainderIsPositiveAndShrinksWithTime() = runBlocking {
        rewardedAgo("c1", cooldownMs - minute)
        val remaining = store.remainingCooldownMs("c1")
        assertTrue("ждали ≈ минуту, получили $remaining", remaining in 1..minute)

        rewardedAgo("c1", 10 * minute)
        assertTrue(store.remainingCooldownMs("c1") > remaining)
    }

    @Test fun atAndAfterTheThresholdTheContainerIsOpenAgain() = runBlocking {
        rewardedAgo("c1", cooldownMs)
        assertEquals("ровно порог — уже можно", 0L, store.remainingCooldownMs("c1"))

        rewardedAgo("c1", cooldownMs + minute)
        assertEquals(0L, store.remainingCooldownMs("c1"))
    }

    @Test fun aLastRewardInTheFutureNeverGivesMoreThanTheFullCooldown() = runBlocking {
        // Часы телефона перевели назад: elapsed отрицательный, остаток считается как есть — больше полного кулдауна (код не зажимает сверху).
        rewardedAgo("c1", -5 * minute)
        assertTrue(store.remainingCooldownMs("c1") > cooldownMs)
    }

    @Test fun containersAreIndependentAndMarkingAgainRestartsTheCountdown() = runBlocking {
        rewardedAgo("c1", cooldownMs + minute)
        store.markRewarded("c2")

        assertEquals(0L, store.remainingCooldownMs("c1"))
        assertTrue(store.remainingCooldownMs("c2") > 0)

        store.markRewarded("c1")
        assertNotNull("повторная отметка перезаписывает ряд контейнера — отсчёт заново", dao.lastRewardedAt("c1"))
        assertTrue(store.remainingCooldownMs("c1") > cooldownMs - minute)
    }

    @Test fun resetAllClearsEveryMark() = runBlocking {
        store.markRewarded("c1")
        store.markRewarded("c2")

        store.resetAll()

        assertEquals(0L, store.remainingCooldownMs("c1"))
        assertEquals(0L, store.remainingCooldownMs("c2"))
        assertNull(dao.lastRewardedAt("c2"))
    }

    @Test fun debugClockSpeedScalesTheCooldown() = runBlocking {
        DebugConfig.clockSpeed = 60.0   // 30 минут → 30 секунд (стенд e2e)
        rewardedAgo("c1", 20_000)
        val remaining = store.remainingCooldownMs("c1")
        assertTrue("ждали ≤ 10 с, получили $remaining", remaining in 1..10_000)

        rewardedAgo("c1", 40_000)
        assertEquals(0L, store.remainingCooldownMs("c1"))
    }
}
