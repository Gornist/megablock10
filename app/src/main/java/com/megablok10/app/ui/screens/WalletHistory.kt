package com.megablok10.app.ui.screens

import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.ui.theme.dayLabel
import java.util.Calendar

/** Сумма входящих минус исходящих за сегодня — null, если сегодня ещё не было ни одной операции. */
internal fun todayInOut(transactions: List<TransactionEntity>, today: Calendar = Calendar.getInstance()): Pair<Long, Long>? {
    val cal = Calendar.getInstance()
    val todayTx = transactions.filter { cal.apply { timeInMillis = it.timestamp }.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR) &&
        cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) }
    if (todayTx.isEmpty()) return null
    val incoming = todayTx.filter { it.amount > 0 }.sumOf { it.amount }
    val outgoing = -todayTx.filter { it.amount < 0 }.sumOf { it.amount }
    return incoming to outgoing
}

/** Тот же принцип, что в ленте чата (ChatScreen.buildChatEntries): день сменился — новая группа с заголовком. */
internal fun groupByDay(transactions: List<TransactionEntity>, today: Calendar = Calendar.getInstance()): List<Pair<String, List<TransactionEntity>>> {
    val cal = Calendar.getInstance()
    val groups = LinkedHashMap<String, MutableList<TransactionEntity>>()
    transactions.forEach { tx ->
        cal.timeInMillis = tx.timestamp
        val label = dayLabel(cal, today)
        groups.getOrPut(label) { mutableListOf() } += tx
    }
    return groups.map { it.key to it.value }
}
