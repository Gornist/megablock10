package com.megablok10.app.ui.screens

import com.megablok10.app.breach.Daemon
import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.items.OutgoingItem
import com.megablok10.app.items.SendItem
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.testing.FakeCharacterDao
import com.megablok10.app.testing.FakeDaemonCollection
import com.megablok10.app.testing.FakeItemLedger
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.FakeShardCollection
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.RecordingNotices
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CyberdeckViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val daemons = FakeDaemonCollection()
    private val shards = FakeShardCollection()
    private val directory = ContactDirectory(ContactStore(FakeCharacterDao(CharacterEntity(bob.key, "Bob", "Арасака"))), MutableStateFlow(emptyList()))
    private val items = FakeItemLedger(alice, "daemon-1")
    private val notices = RecordingNotices()

    private fun TestScope.deck(
        applyRamUpgrade: suspend (Mb10Qr.RamUpgrade) -> Int? = { null },
        applyGrant: suspend (Mb10Qr.LootGrant) -> String? = { null },
    ) = CyberdeckViewModel(
        MutableStateFlow(alice.identity), daemons, shards, directory, applyRamUpgrade, applyGrant,
        SendItem(items, FakeMessenger(bob.peer)), notices, this,
    )

    @Test fun newCharacterGetsTheStartingDaemonSeededExactlyOnce() = runTest {
        val identity = MutableStateFlow(alice.identity)
        val vm = CyberdeckViewModel(identity, daemons, shards, directory, { null }, { null }, SendItem(items, FakeMessenger()), notices, this)
        backgroundScope.launch { vm.state.collect {} }
        runCurrent()

        assertEquals(1, daemons.seedCalls)
        assertTrue("стартовый демон появился в коллекции", daemons.items.value.isNotEmpty())

        // Тот же персонаж дальше не пересеивается (сброс сессии на том же ключе — другая история, id не меняется).
        identity.value = alice.identity.copy(callsign = "Alice2")
        runCurrent()
        assertEquals(1, daemons.seedCalls)
    }

    @Test fun stateCombinesDaemonsShardsAndContacts() = runTest {
        daemons.items.value = listOf(Daemon("d1", "Ghostwalker", listOf("1C", "55")))
        val vm = deck()
        backgroundScope.launch { vm.state.collect {} }
        runCurrent()

        assertEquals(listOf("Ghostwalker"), vm.state.value.daemons.map { it.name })
        assertEquals(listOf("Bob"), vm.state.value.contacts.contacts.map { it.callsign })
    }

    @Test fun scanningAShardAddsItAndOpensTheShardsSegment() = runTest {
        val vm = deck()
        val shard = Mb10Qr.Shard(id = "s1", decryptAction = false, tier = 1, valueHint = "низкий", title = "Обрывок", meta = "", body = "")

        vm.onScan(shard)
        runCurrent()

        assertEquals(listOf(shard), shards.items.value)
        assertEquals(CyberdeckViewModel.SEGMENT_SHARDS, vm.segment.value)
    }

    @Test fun scanningARamTokenShowsTheResultAsANotice() = runTest {
        val vm = deck(applyRamUpgrade = { 8 })

        vm.onScan(Mb10Qr.RamUpgrade(token = "tok-1", delta = 2))
        runCurrent()

        assertEquals(listOf("RAM деки увеличена до 8"), notices.shown)
    }

    @Test fun markDecryptedDelegatesToTheShardCollection() = runTest {
        shards.items.value = listOf(Mb10Qr.Shard(id = "s1", decryptAction = true, tier = 1, valueHint = "", title = "", meta = "", body = "", decrypted = false))
        val vm = deck()

        vm.markDecrypted("s1")
        runCurrent()

        assertEquals(listOf("s1"), shards.decryptedIds)
        assertTrue(shards.items.value.single().decrypted)
    }

    @Test fun successfulTransferNotifiesAndCallsBackOnTheMainThread() = runTest {
        val vm = deck()
        var closed = false

        vm.transfer(OutgoingItem.Daemon(Daemon("daemon-1", "Ghostwalker", listOf("1C"))), bob.key, label = "Ghostwalker") { closed = true }
        runCurrent()

        assertTrue("экран закрывает карточку предмета после отправки", closed)
        assertEquals(listOf("Передача отправлена: Ghostwalker"), notices.shown)
    }

    @Test fun failedTransferIsExplainedInsteadOfSilentlyClosing() = runTest {
        val vm = deck()
        var closed = false

        // Предмета с таким id нет в FakeItemLedger — SendItem вернёт null.
        vm.transfer(OutgoingItem.Shard("no-such-shard"), bob.key, label = "?") { closed = true }
        runCurrent()

        assertTrue("не закрываем карточку, которую не удалось передать", !closed)
        assertEquals(listOf("Не удалось передать"), notices.shown)
    }
}
