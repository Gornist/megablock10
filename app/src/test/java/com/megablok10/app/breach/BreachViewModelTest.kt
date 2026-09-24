package com.megablok10.app.breach

import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.RecordedChanges
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BreachViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val me = TestPlayer("Razor")
    private val changes = RecordedChanges(me)
    private val node = Container("node-7", "Узел 7", Tier.BASE, ownerFaction = "", loot = emptyList())
    private var cooldownMs = 0L
    private val reward = RewardOutcome(10, emptyList(), emptyList(), cacheExhausted = false, matchedEffects = emptySet())

    private fun TestScope.breach() = BreachViewModel(
        identity = MutableStateFlow(me.identity),
        checkAccess = CheckBreachAccess({ true }, { cooldownMs }, { false }, changes.recorder),
        finishBreach = FinishBreach(changes.recorder, { _, _, _, _ -> reward }, {}, { _, _, _, _ -> }),
        work = this,
    )

    @Test fun openNodeOpensTheBreachAndClosingReturnsToTheDeck() = runTest {
        val vm = breach()

        vm.open(node)
        runCurrent()
        assertEquals(node, vm.container.value)
        assertNull(vm.issue.value)

        vm.close()
        assertNull(vm.container.value)
    }

    @Test fun coolingNodeShowsTheReasonAndANewScanClearsIt() = runTest {
        val vm = breach()
        cooldownMs = 90_000

        vm.open(node)
        runCurrent()
        assertEquals(BreachAccess.Blocked(BreachBlock.COOLDOWN, cooldownMinutes = 2), vm.issue.value)
        assertNull(vm.container.value)

        cooldownMs = 0
        vm.open(node)
        assertNull("новый скан убирает старую причину сразу", vm.issue.value)
        runCurrent()
        assertEquals(node, vm.container.value)
    }

    @Test fun finishedBreachHandsTheRewardBackToTheScreen() = runTest {
        val vm = breach()
        var shown: RewardOutcome? = null

        vm.finish(node, BreachResult(emptyList(), emptySet()), seed = 3) { shown = it }
        runCurrent()

        assertEquals(reward, shown)
        assertEquals("node-7:3", changes.rows.single().sourceRef)
    }
}
