package com.megablok10.app.ui.screens

import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar

class WalletHistoryTest {
    private val today = Calendar.getInstance().apply { set(2026, Calendar.OCTOBER, 4, 15, 0, 0) }

    private fun at(daysAgo: Int, hour: Int = 12): Long =
        (today.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -daysAgo); set(Calendar.HOUR_OF_DAY, hour) }.timeInMillis

    private fun tx(id: String, amount: Long, ts: Long) =
        TransactionEntity(id = id, counterpartyPubKeyB64 = "k", amount = amount, memo = "", timestamp = ts, status = TransactionStatus.CONFIRMED)

    @Test fun noOperationsToday() {
        assertNull(todayInOut(emptyList(), today))
        assertNull(todayInOut(listOf(tx("1", 10, at(1))), today))
    }

    @Test fun todayTotalsSplitIncomingAndOutgoingAndIgnoreOtherDays() {
        val list = listOf(tx("1", 300, at(0, 9)), tx("2", -120, at(0, 10)), tx("3", -50, at(0, 11)), tx("4", 999, at(1)))

        assertEquals(300L to 170L, todayInOut(list, today))
    }

    @Test fun sameDayOfYearInAnotherYearIsNotToday() {
        val lastYear = (today.clone() as Calendar).apply { add(Calendar.YEAR, -1) }.timeInMillis

        assertNull(todayInOut(listOf(tx("1", 10, lastYear)), today))
    }

    @Test fun groupsKeepTheListOrderAndTitleTheDays() {
        val list = listOf(tx("1", 1, at(0, 14)), tx("2", 2, at(0, 8)), tx("3", 3, at(1)), tx("4", 4, at(5)))

        val groups = groupByDay(list, today)

        assertEquals(listOf("Сегодня", "Вчера", "29 сентября"), groups.map { it.first })
        assertEquals(listOf(listOf("1", "2"), listOf("3"), listOf("4")), groups.map { g -> g.second.map { it.id } })
    }
}
