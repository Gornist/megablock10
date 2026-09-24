package com.megablok10.app.wallet

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Правило списания из TransactionStore.recordOutgoingPending (см. BalanceRules.kt), покрыто отдельно от Room/Context. */
class BalanceRulesTest {

    @Test fun `positive amount not exceeding the balance can be debited`() {
        assertTrue(canDebit(amount = 1, currentBalance = 1))
        assertTrue(canDebit(amount = 300, currentBalance = 1_000))
        assertTrue(canDebit(amount = 1_000, currentBalance = 1_000))
    }

    @Test fun `amount exceeding the balance is rejected — this is what keeps two quick taps from double-spending`() {
        assertFalse(canDebit(amount = 1_001, currentBalance = 1_000))
        assertFalse(canDebit(amount = 1, currentBalance = 0))
    }

    @Test fun `zero or negative amount is rejected regardless of balance`() {
        assertFalse(canDebit(amount = 0, currentBalance = 1_000))
        assertFalse(canDebit(amount = -1, currentBalance = 1_000))
    }

    @Test fun `negative balance (already overdrawn) rejects any further debit`() {
        assertFalse(canDebit(amount = 1, currentBalance = -50))
    }
}
