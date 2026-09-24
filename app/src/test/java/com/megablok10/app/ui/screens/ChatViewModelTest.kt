package com.megablok10.app.ui.screens

import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.testing.FakeCharacterDao
import com.megablok10.app.testing.FakeChatInbox
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ChatViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val alice = TestPlayer("Alice", faction = "Малстром")
    private val bob = TestPlayer("Bob")
    private val chat = FakeChatInbox()
    private val directory = ContactDirectory(ContactStore(FakeCharacterDao(CharacterEntity(bob.key, "Bob", "Арасака"))), MutableStateFlow(emptyList()))

    private fun msg(faction: String, body: String) = ChatMessageEntity(type = "FACTION", fromPubKeyB64 = alice.key, fromCallsign = alice.callsign, faction = faction, toPubKeyB64 = "", body = body, timestamp = 1L)

    @Test fun stateFollowsTheCurrentFactionAndDirectThreadsOfTheCurrentCharacter() = runTest {
        val identity = MutableStateFlow(alice.identity)
        val vm = ChatViewModel(identity, chat, directory, this)
        backgroundScope.launch { vm.state.collect {} }
        runCurrent()

        chat.factionFeed("Малстром").value = listOf(msg("Малстром", "сбор в 20:00"))
        chat.recentThreads.value = listOf(msg("", "привет"))
        runCurrent()

        assertEquals(listOf("сбор в 20:00"), vm.state.value.factionMessages.map { it.body })
        assertEquals(listOf("привет"), vm.state.value.recentThreads.map { it.body })
        assertEquals(listOf("Bob"), vm.state.value.contacts.contacts.map { it.callsign })
    }

    @Test fun masterSwitchingTheFactionMovesTheInboxToTheNewFactionsFeed() = runTest {
        val identity = MutableStateFlow(alice.identity)
        val vm = ChatViewModel(identity, chat, directory, this)
        backgroundScope.launch { vm.state.collect {} }
        chat.factionFeed("Малстром").value = listOf(msg("Малстром", "старая фракция"))
        runCurrent()
        assertEquals(listOf("старая фракция"), vm.state.value.factionMessages.map { it.body })

        identity.value = alice.identity.copy(faction = "Ночная Стая")
        chat.factionFeed("Ночная Стая").value = listOf(msg("Ночная Стая", "новая фракция"))
        runCurrent()

        assertEquals(listOf("новая фракция"), vm.state.value.factionMessages.map { it.body })
    }

    @Test fun sendFactionDelegatesToTheInboxWithTheCurrentCharacter() = runTest {
        val vm = ChatViewModel(MutableStateFlow(alice.identity), chat, directory, this)

        vm.sendFaction("на связи")
        runCurrent()

        assertEquals(listOf("на связи"), chat.sentFaction)
    }
}
