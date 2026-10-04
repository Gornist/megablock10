package com.megablok10.app.ui.screens

import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.testing.FakeCharacterDao
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.FakePaymentLedger
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.RecordingNotices
import com.megablok10.app.testing.TestPlayer
import com.megablok10.app.wallet.SendPayment
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class WalletViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val ledger = FakePaymentLedger(alice, balance = 50)
    private val peers = MutableStateFlow(listOf(bob.peer))
    private val directory = ContactDirectory(ContactStore(FakeCharacterDao(CharacterEntity(bob.key, "Bob", "Арасака"))), peers)
    private val notices = RecordingNotices()

    @Test fun stateShowsBalanceHistoryAndWhoIsOnline() = runTest {
        val vm = WalletViewModel(MutableStateFlow(alice.identity), ledger, directory, SendPayment(ledger, FakeMessenger(bob.peer)), notices, this)
        backgroundScope.launch { vm.state.collect {} }
        val tx = TransactionEntity("tx-1", bob.key, -10, "", 1L, TransactionStatus.CONFIRMED)

        ledger.entries.value = listOf(tx)
        ledger.balance = 40
        runCurrent()

        val state = vm.state.value
        assertEquals(40, state.balance)
        assertEquals(listOf(tx), state.transactions)
        assertEquals(listOf("Bob"), state.contacts.contacts.map { it.callsign })
        assertEquals(setOf(bob.key), state.contacts.onlineKeys)

        peers.value = emptyList()
        runCurrent()
        assertTrue("Боб ушёл из сети", vm.state.value.contacts.onlineKeys.isEmpty())
    }

    @Test fun sentPaymentIsDebitedAndDeliveredWithTheFormsId() = runTest {
        val chat = FakeMessenger(bob.peer)
        val vm = WalletViewModel(MutableStateFlow(alice.identity), ledger, directory, SendPayment(ledger, chat), notices, this)

        vm.send(bob.key, id = "form-1", amount = 20, memo = "долг")
        runCurrent()

        assertEquals(30, ledger.balance)
        assertEquals(TransactionStatus.DELIVERED, ledger.status["form-1"])
        assertTrue(notices.shown.isEmpty())
    }

    @Test fun refusedPaymentIsExplainedInsteadOfSilentlyShowingAPhantomTransfer() = runTest {
        val vm = WalletViewModel(MutableStateFlow(alice.identity), ledger, directory, SendPayment(ledger, FakeMessenger(bob.peer)), notices, this)

        vm.send(bob.key, id = "form-1", amount = 80, memo = "")
        runCurrent()

        assertEquals(50, ledger.balance)
        assertEquals(listOf("Перевод не прошёл: на балансе не хватает денег"), notices.shown)
    }

    @Test fun cancelReturnsAnUndeliveredPayment() = runTest {
        val vm = WalletViewModel(MutableStateFlow(alice.identity), ledger, directory, SendPayment(ledger, FakeMessenger()), notices, this)

        vm.send(bob.key, id = "form-1", amount = 20, memo = "")
        runCurrent()
        vm.cancel("form-1")
        runCurrent()

        assertTrue(ledger.status.isEmpty())
    }

    private fun vmIn(scope: kotlinx.coroutines.CoroutineScope) =
        WalletViewModel(MutableStateFlow(alice.identity), ledger, directory, SendPayment(ledger, FakeMessenger(bob.peer)), notices, scope)

    @Test fun amountEqualToTheBalanceIsAllowed() = runTest {
        assertEquals(AmountCheck.Valid(50), vmIn(this).validate("50", balance = 50))
    }

    @Test fun amountAboveTheBalanceIsRefusedWithAFundsMessage() = runTest {
        val check = vmIn(this).validate("51", balance = 50)

        assertEquals(AmountCheck.ExceedsBalance, check)
        assertEquals("недостаточно средств", check.errorText)
    }

    @Test fun zeroNegativeAndNonNumericAmountsAskForAPositiveSum() = runTest {
        val vm = vmIn(this)

        for (text in listOf("0", "-5", "abc", "1.5", " 5", "12 3", "99999999999999999999")) {
            val check = vm.validate(text, balance = 50)
            assertEquals(text, AmountCheck.NotPositive, check)
            assertEquals(text, "введите сумму больше нуля", check.errorText)
        }
    }

    @Test fun emptyAmountIsNeitherValidNorAnError() = runTest {
        val check = vmIn(this).validate("", balance = 50)

        assertEquals(AmountCheck.Empty, check)
        assertNull(check.errorText)
    }

    @Test fun anyPositiveAmountIsRefusedWhenTheBalanceIsEmpty() = runTest {
        assertEquals(AmountCheck.ExceedsBalance, vmIn(this).validate("1", balance = 0))
    }

    @Test fun validAmountHasNoErrorText() = runTest {
        assertNull(vmIn(this).validate("20", balance = 50).errorText)
    }

    @Test fun everyNewPaymentGetsItsOwnId() = runTest {
        val vm = vmIn(this)

        assertNotEquals(vm.newPaymentId(), vm.newPaymentId())
    }
}
