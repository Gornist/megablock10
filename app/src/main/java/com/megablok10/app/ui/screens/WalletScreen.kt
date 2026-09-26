package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.di.walletViewModel
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbAmountField
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDialogTone
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbField
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbListItemState
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbStatusText
import com.megablok10.app.ui.theme.MbStatusTone
import com.megablok10.app.ui.theme.MbTile
import com.megablok10.app.ui.theme.MbTileTone
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.formatMoney
import com.megablok10.app.ui.theme.groupThousands
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.UUID

/**
 * Хэндшейк перевода идёт сообщениями в личном чате с получателем, а не показыванием QR друг другу: получатель выбирается
 * из контактов сразу, подписанная транзакция и чек-подтверждение — телом обычного DM-сообщения (см. ChatScreen — там же
 * рисуются платёжные "пузыри" с кнопкой "Принять"). QR остаётся только для контактов, точек доступа и шардов — не для денег.
 */
@Composable
fun WalletScreen(presetContactKey: String? = null, onPresetConsumed: () -> Unit = {}) {
    val wallet = appViewModel { walletViewModel() }
    val state by wallet.state.collectAsStateWithLifecycle()
    val balance = state.balance
    val transactions = state.transactions
    val contacts = state.contacts.contacts
    val contactsByKey = remember(contacts) { contacts.associateBy { it.publicKeyB64 } }
    val onlineKeys = state.contacts.onlineKeys

    var sending by remember { mutableStateOf(false) }
    // Пришли из треда чата: сразу открываем форму с уже выбранным получателем.
    var presetKey by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(presetContactKey) {
        if (presetContactKey != null) { presetKey = presetContactKey; sending = true; onPresetConsumed() }
    }

    val todayTotals = remember(transactions) { todayInOut(transactions) }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbTile(
            modifier = Modifier.fillMaxWidth(),
            label = "Баланс",
            value = groupThousands(balance),
            valueUnit = "€$",
            tone = MbTileTone.Money,
            big = true,
            subItems = if (todayTotals == null) emptyList() else listOf(
                "+${groupThousands(todayTotals.first)} за сутки",
                "−${groupThousands(todayTotals.second)} отправлено"
            )
        )
        Row(Modifier.fillMaxWidth().padding(vertical = MbDimens.blockGap)) {
            MbButton("Новый платёж", onClick = { sending = true })
        }

        if (transactions.isEmpty()) {
            Box(Modifier.weight(1f)) { MbEmptyState(MbIcons.Wallet, "Пока пусто", "Ещё не было ни одной транзакции.") }
        } else {
            val groups = remember(transactions) { groupByDay(transactions) }
            LazyColumn(Modifier.weight(1f)) {
                groups.forEach { (label, txs) ->
                    item { MbSectionTitle(label) }
                    items(txs, key = { it.id }) { tx ->
                        TxRow(tx = tx, counterpartyName = contactsByKey[tx.counterpartyPubKeyB64]?.callsign, onCancelPending = { wallet.cancel(tx.id) })
                    }
                }
            }
        }
    }

    if (sending) {
        SendTransactionDialog(
            contacts = contacts,
            onlineKeys = onlineKeys,
            transactions = transactions,
            balance = balance,
            initialContact = contacts.find { it.publicKeyB64 == presetKey },
            onSend = { contact, id, amount, memo -> wallet.send(contact.publicKeyB64, id, amount, memo) },
            onCancel = wallet::cancel,
            onDismiss = { sending = false; presetKey = null }
        )
    }
}

/** Сумма входящих минус исходящих за сегодня — null, если сегодня ещё не было ни одной операции. */
private fun todayInOut(transactions: List<TransactionEntity>): Pair<Long, Long>? {
    val cal = Calendar.getInstance()
    val today = Calendar.getInstance()
    val todayTx = transactions.filter { cal.apply { timeInMillis = it.timestamp }.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR) &&
        cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) }
    if (todayTx.isEmpty()) return null
    val incoming = todayTx.filter { it.amount > 0 }.sumOf { it.amount }
    val outgoing = -todayTx.filter { it.amount < 0 }.sumOf { it.amount }
    return incoming to outgoing
}

/** Тот же принцип, что в ленте чата (ChatScreen.buildChatEntries): день сменился — новая группа с заголовком. */
private fun groupByDay(transactions: List<TransactionEntity>): List<Pair<String, List<TransactionEntity>>> {
    val cal = Calendar.getInstance()
    val today = Calendar.getInstance()
    val groups = LinkedHashMap<String, MutableList<TransactionEntity>>()
    transactions.forEach { tx ->
        cal.timeInMillis = tx.timestamp
        val label = dayLabelFor(cal, today)
        groups.getOrPut(label) { mutableListOf() } += tx
    }
    return groups.map { it.key to it.value }
}

private fun dayLabelFor(day: Calendar, today: Calendar): String {
    val sameYear = today.get(Calendar.YEAR) == day.get(Calendar.YEAR)
    val diff = today.get(Calendar.DAY_OF_YEAR) - day.get(Calendar.DAY_OF_YEAR)
    return when {
        sameYear && diff == 0 -> "Сегодня"
        sameYear && diff == 1 -> "Вчера"
        else -> SimpleDateFormat("d MMMM", Locale("ru")).format(day.time)
    }
}

@Composable
internal fun TxRow(tx: TransactionEntity, counterpartyName: String?, onCancelPending: () -> Unit) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val c = LocalMbColors.current
    val pending = tx.status == TransactionStatus.PENDING
    val delivered = tx.status == TransactionStatus.DELIVERED
    val incoming = tx.amount > 0
    val tone = when { pending -> c.bad; delivered -> c.warn; incoming -> c.ok; else -> c.ink }
    val icon = when { pending -> MbIcons.Close; incoming -> MbIcons.In; else -> MbIcons.Out }
    val title = tx.memo.ifBlank { if (incoming) "Входящий платёж" else "Платёж" }
    val counterpartyText = if (tx.counterpartyPubKeyB64.isEmpty()) {
        null
    } else {
        val label = counterpartyName ?: (tx.counterpartyPubKeyB64.take(8) + "…")
        if (incoming) "от $label" else "→ $label"
    }
    MbListItem(
        title = title,
        sub = listOfNotNull(counterpartyText).joinToString(),
        lead = { Icon(painterResource(icon), contentDescription = null, tint = tone) },
        trail = listOfNotNull(
            { Text((if (incoming) "+" else "") + formatMoney(tx.amount), style = MbTypography.listAmount, color = tone) },
            if (pending) {
                { MbStatusText("не доставлено", MbStatusTone.Bad) }
            } else if (delivered) {
                { MbStatusText("доставлено, ждёт принятия", MbStatusTone.Warn) }
            } else null,
            { Text(timeFormat.format(tx.timestamp), style = MbTypography.meta, color = c.ink2) },
            if (pending) { { MbButton("Отменить", onClick = onCancelPending, kind = MbButtonKind.Danger, inline = true) } } else null
        )
    )
}

private data class SentPayment(val id: String, val contact: Mb10Qr.Contact, val amount: Long, val memo: String)

@Composable
private fun SendTransactionDialog(
    contacts: List<Mb10Qr.Contact>,
    onlineKeys: Set<String>,
    transactions: List<TransactionEntity>,
    balance: Long,
    initialContact: Mb10Qr.Contact? = null,
    onSend: (contact: Mb10Qr.Contact, id: String, amount: Long, memo: String) -> Unit,
    onCancel: (id: String) -> Unit,
    onDismiss: () -> Unit
) {
    var selectedContact by remember { mutableStateOf(initialContact) }
    // Список контактов приходит из БД уже после первой композиции — подставляем получателя, когда он появится.
    LaunchedEffect(initialContact) { if (selectedContact == null && initialContact != null) selectedContact = initialContact }
    var sent by remember { mutableStateOf<SentPayment?>(null) }
    var amountText by remember { mutableStateOf("") }
    var memoText by remember { mutableStateOf("") }
    val c = LocalMbColors.current

    val activeSent = sent
    val contact = selectedContact
    MbDialog(
        onDismissRequest = onDismiss,
        icon = MbIcons.Wallet,
        title = when {
            activeSent != null -> "Перевод"
            contact == null -> "Кому отправить"
            else -> "Перевод · ${contact.callsign}"
        },
        tone = MbDialogTone.Default,
        actions = when {
            activeSent != null -> {
                val status = transactions.find { it.id == activeSent.id }?.status
                when (status) {
                    TransactionStatus.CONFIRMED -> listOf(MbDialogAction("Закрыть", MbButtonKind.Quiet, onClick = onDismiss))
                    TransactionStatus.PENDING -> listOf(
                        MbDialogAction("Отменить платёж", MbButtonKind.Danger) { onCancel(activeSent.id); sent = null; selectedContact = null },
                        MbDialogAction("Закрыть", MbButtonKind.Quiet, onClick = onDismiss)
                    )
                    else -> listOf(MbDialogAction("Закрыть", MbButtonKind.Quiet, onClick = onDismiss))
                }
            }
            contact == null -> listOf(MbDialogAction("Отмена", MbButtonKind.Quiet, onClick = onDismiss))
            else -> {
                val parsedAmount = amountText.toLongOrNull()
                val amountValid = parsedAmount != null && parsedAmount > 0 && parsedAmount <= balance
                listOf(
                    MbDialogAction("Отмена", MbButtonKind.Quiet, onClick = { selectedContact = null }),
                    MbDialogAction("Отправить", if (amountValid) MbButtonKind.Success else MbButtonKind.Quiet) {
                        if (amountValid) {
                            val id = UUID.randomUUID().toString()
                            val amount = amountText.toLong()
                            onSend(contact, id, amount, memoText)
                            sent = SentPayment(id, contact, amount, memoText)
                        }
                    }
                )
            }
        },
        wideActions = activeSent == null && contact != null
    ) {
        when {
            activeSent != null -> {
                val status = transactions.find { it.id == activeSent.id }?.status
                Text(formatMoney(activeSent.amount) + if (activeSent.memo.isNotBlank()) " · ${activeSent.memo}" else "", style = MbTypography.dialogText, color = c.ink)
                when (status) {
                    TransactionStatus.CONFIRMED -> MbStatusText("подтверждено", MbStatusTone.Ok)
                    TransactionStatus.DELIVERED -> {
                        MbStatusText("доставлено, ждёт принятия", MbStatusTone.Warn)
                        Text("Карточка уже у получателя — отменить платёж нельзя, ждём, пока он примет его в чате.", style = MbTypography.meta, color = c.ink2)
                    }
                    else -> {
                        MbStatusText("не доставлено", MbStatusTone.Bad)
                        Text("Получатель не в сети — карточка ему не дошла. Пока это так, платёж можно отменить и вернуть деньги.", style = MbTypography.meta, color = c.ink2)
                    }
                }
            }
            contact == null -> {
                if (contacts.isEmpty()) {
                    Text("Нет добавленных контактов — сначала отсканируйте QR-код игрока в Профиле.", style = MbTypography.dialogText, color = c.ink2)
                } else {
                    contacts.forEach { contact2 ->
                        val online = contact2.publicKeyB64 in onlineKeys
                        MbListItem(
                            title = contact2.callsign,
                            sub = contact2.faction,
                            lead = { Icon(painterResource(MbIcons.User), contentDescription = null) },
                            state = if (online) MbListItemState.Normal else MbListItemState.Off,
                            onClick = { selectedContact = contact2 }
                        )
                    }
                }
            }
            else -> {
                val parsedAmount = amountText.toLongOrNull()
                val showError = amountText.isNotEmpty() && (parsedAmount == null || parsedAmount <= 0 || parsedAmount > balance)
                Text(
                    "Сумма списывается с вашего баланса сразу — как передать наличные из рук в руки. Перевод уйдёт получателю сообщением в чат — до его подтверждения платёж ещё можно отменить.",
                    style = MbTypography.meta, color = c.ink2
                )
                MbAmountField(value = amountText, onValueChange = { amountText = it })
                if (showError) {
                    MbStatusText(if (parsedAmount != null && parsedAmount > balance) "недостаточно средств" else "введите сумму больше нуля", MbStatusTone.Bad)
                }
                MbField(value = memoText, onValueChange = { memoText = it }, placeholder = "За что (необязательно)")
            }
        }
    }
}
