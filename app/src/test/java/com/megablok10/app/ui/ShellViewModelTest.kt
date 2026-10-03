package com.megablok10.app.ui

import com.megablok10.app.identity.Identity
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.ui.nav.AppTab
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ShellViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val identity = MutableStateFlow<Identity?>(Identity("alice", "Alice", "Малстром"))
    private val balance = MutableStateFlow(0L)
    private val missed = MutableStateFlow(0)
    private val unreadFor = mutableMapOf<String, MutableStateFlow<Int>>()
    private var chatSeen = 0
    private var callsSeen = 0

    private fun vm() = ShellViewModel(
        identity = identity,
        balance = balance,
        unreadChatThreads = { key -> unreadFor.getOrPut(key) { MutableStateFlow(0) } },
        missedCalls = missed,
        markChatSeen = { chatSeen++ },
        markCallsSeen = { callsSeen++ },
    )

    private fun TestScope.collectAll(model: ShellViewModel) {
        backgroundScope.launch { model.balance.collect {} }
        backgroundScope.launch { model.unreadChat.collect {} }
        backgroundScope.launch { model.missedCalls.collect {} }
        runCurrent()
    }

    @Test fun badgesAndBalanceFollowTheSources() = runTest {
        val model = vm()
        collectAll(model)

        balance.value = 1240
        missed.value = 2
        unreadFor.getValue("alice").value = 3
        runCurrent()

        assertEquals(1240L, model.balance.value)
        assertEquals(2, model.missedCalls.value)
        assertEquals(3, model.unreadChat.value)
    }

    @Test fun unreadChatSwitchesToTheNewCharacterAndDropsToZeroWithoutOne() = runTest {
        val model = vm()
        collectAll(model)
        unreadFor.getValue("alice").value = 3
        runCurrent()

        identity.value = null
        runCurrent()
        assertEquals(0, model.unreadChat.value)

        unreadFor.getOrPut("bob") { MutableStateFlow(5) }
        identity.value = Identity("bob", "Bob", "Арасака")
        runCurrent()
        assertEquals(5, model.unreadChat.value)
    }

    @Test fun shownTabClearsItsOwnBadgeOnly() {
        val model = vm()

        model.onTabShown(AppTab.Chat)
        model.onTabShown(AppTab.Calls)
        model.onTabShown(AppTab.Hack)
        model.onTabShown(AppTab.Wallet)

        assertEquals(1, chatSeen)
        assertEquals(1, callsSeen)
    }
}
