package com.megablok10.app.ui.screens

import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.testing.FakeCallControls
import com.megablok10.app.testing.FakeCharacterDao
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CallsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val calls = FakeCallControls()
    private val directory = ContactDirectory(ContactStore(FakeCharacterDao(CharacterEntity(bob.key, "Bob", "Арасака"))), MutableStateFlow(emptyList()))

    @Test fun exposesTheCallStateLogAndContactsAsIs() = runTest {
        calls.state.value = CallUiState(phase = CallPhase.IN_CALL, peerCallsign = "Bob")
        val vm = CallsViewModel(calls, MutableStateFlow(alice.identity), directory)
        backgroundScope.launch { vm.log.collect {} }
        backgroundScope.launch { vm.contacts.collect {} }
        runCurrent()

        assertEquals(CallPhase.IN_CALL, vm.call.value.phase)
        assertEquals(listOf("Bob"), vm.contacts.value.contacts.map { it.callsign })
    }

    @Test fun startAcceptAndEndActOnlyWhenACharacterIsPresent() = runTest {
        val identity = MutableStateFlow<com.megablok10.app.identity.Identity?>(null)
        val vm = CallsViewModel(calls, identity, directory)

        vm.start(bob.peer)
        vm.accept()
        vm.end()
        assertTrue("без персонажа звонок не начинается", calls.started.isEmpty())
        assertEquals(0, calls.accepted)
        assertEquals(0, calls.ended)

        identity.value = alice.identity
        vm.start(bob.peer)
        vm.accept()
        vm.end()

        assertEquals(listOf(bob.peer), calls.started)
        assertEquals(1, calls.accepted)
        assertEquals(1, calls.ended)
    }
}
