package com.megablok10.app.breach

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.identity.Identity
import com.megablok10.app.testing.RecordedChanges
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сценарии CheckBreachAccess и FinishBreach: порядок проверок, записи для мастера, награда, остывание, сигнал СБ. */
class BreachScenariosTest {
    private val me = TestPlayer("Razor")
    private val changes = RecordedChanges(me)
    private val container = Container("node-7", "Узел 7", Tier.HARD, ownerFaction = "Арасака", loot = emptyList())

    private var online = true
    private var cooldownMs = 0L
    private var exhausted = false
    private val asked = mutableListOf<String>()
    private val check = CheckBreachAccess(
        isOnline = { asked += "online"; online },
        cooldownRemainingMs = { asked += "cooldown:$it"; cooldownMs },
        isExhausted = { asked += "exhausted:${it.id}"; exhausted },
        changes = changes.recorder,
    )

    @Test fun openNodeIsNotRecorded() = runTest {
        assertEquals(BreachAccess.Open, check(me.identity, container))
        assertEquals(listOf("online", "cooldown:node-7", "exhausted:node-7"), asked)
        assertTrue(changes.rows.isEmpty())
    }

    @Test fun withoutLinkNothingElseIsCheckedAndTheBlockIsReported() = runTest {
        online = false
        cooldownMs = 10_000
        exhausted = true

        assertEquals(BreachAccess.Blocked(BreachBlock.NO_LINK), check(me.identity, container))
        assertEquals(listOf("online"), asked)
        val record = changes.rows.single()
        assertEquals(ChangeField.COUNTERS_BLOCKED, record.field)
        assertEquals("""{"reason":"NO_LINK"}""", record.newValue)
        assertEquals(ChangeReason.BREACH_BLOCKED, record.reason)
        assertEquals("node-7", record.sourceRef)
        assertEquals(me.key, record.subjectKeyB64)
    }

    @Test fun coolingNodeReportsMinutesRoundedUp() = runTest {
        cooldownMs = 1

        assertEquals(BreachAccess.Blocked(BreachBlock.COOLDOWN, cooldownMinutes = 1), check(me.identity, container))
        assertEquals("""{"reason":"COOLDOWN"}""", changes.rows.single().newValue)
        assertEquals(3, CheckBreachAccess.cooldownMinutes(2 * 60_000L + 1))
    }

    @Test fun exhaustedNodeIsBlockedBeforeTheAttemptIsSpent() = runTest {
        exhausted = true

        assertEquals(BreachAccess.Blocked(BreachBlock.EXHAUSTED), check(me.identity, container))
        assertEquals("""{"reason":"EXHAUSTED"}""", changes.rows.single().newValue)
    }

    private val calls = mutableListOf<String>()
    private val reward = RewardOutcome(eddies = 40, extractedShardTitles = listOf("Досье"), extractedDaemonNames = emptyList(), cacheExhausted = false, matchedEffects = setOf(DaemonEffect.BLACKOUT))
    private val finish = FinishBreach(
        changes = changes.recorder,
        applyRewards = { who: Identity, c, _, attemptId -> calls += "rewards:${who.callsign}:${c.id}:$attemptId"; reward },
        markRewarded = { calls += "cooldown:$it" },
        raiseAlert = { _, c, outcome, effects -> calls += "alert:${c.id}:$outcome:$effects" },
    )
    private val ghost = Daemon("ghost", "Тень", listOf("1C"))
    private val razor = Daemon("razor", "Бритва", listOf("55"))

    @Test fun finishedAttemptIsRecordedRewardedCooledDownAndReportedToSecurity() = runTest {
        val result = BreachResult(allDaemons = listOf(ghost, razor), matchedIds = setOf("ghost"))

        assertEquals(reward, finish(me.identity, container, result, seed = 42))

        val record = changes.rows.single()
        assertEquals(ChangeField.COUNTERS_BREACH, record.field)
        assertEquals("""{"tier":"HARD","outcome":"partial"}""", record.newValue)
        assertEquals(ChangeReason.BREACH_ATTEMPT, record.reason)
        assertEquals("node-7:42", record.sourceRef)
        assertEquals(
            listOf("rewards:Razor:node-7:node-7:42", "cooldown:node-7", "alert:node-7:PARTIAL:[BLACKOUT]"),
            calls,
        )
    }

    @Test fun failedAttemptDoesNotCoolTheNodeButStillAlerts() = runTest {
        finish(me.identity, container, BreachResult(allDaemons = listOf(ghost), matchedIds = emptySet()), seed = 7)

        assertEquals("""{"tier":"HARD","outcome":"fail"}""", changes.rows.single().newValue)
        assertEquals(listOf("rewards:Razor:node-7:node-7:7", "alert:node-7:FAIL:[BLACKOUT]"), calls)
    }
}
