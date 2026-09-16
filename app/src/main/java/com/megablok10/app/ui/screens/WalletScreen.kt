package com.megablok10.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.ui.theme.AmountField
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.ChipTone
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.ui.theme.StatusChip
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

/**
 * Хэндшейк перевода теперь идёт сообщениями в личном чате с получателем, а
 * не показыванием QR друг другу: получатель выбирается из контактов сразу
 * (а не определяется тем, кто отсканировал QR), подписанная транзакция и
 * чек-подтверждение — та же сериализация, что раньше шла в QR-картинку,
 * просто телом обычного DM-сообщения (см. ChatScreen — там же и рисуются
 * платёжные "пузыри" с кнопкой "Принять"). QR остаётся только для контактов,
 * точек доступа и шардов — не для денег.
 */
@Composable
fun WalletScreen(identity: Identity) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val balance by TransactionStore.observeBalance(context).collectAsState(initial = 0L)
    val transactions by TransactionStore.observeAll(context).collectAsState(initial = emptyList())
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val contactsByKey = remember(contacts) { contacts.associateBy { it.publicKeyB64 } }
    val onlinePeers by PresenceService.peers.collectAsState()
    val onlineKeys = remember(onlinePeers) { onlinePeers.map { it.pubKeyB64 }.toSet() }

    var sending by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionLabel("Баланс")
        ChamferedPanel(
            borderColor = MB10Colors.borderMuted,
            fillColor = MB10Colors.surfaceSunken,
            cut = 10.dp,
            doubleCorner = true,
            contentPadding = 16.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column {
                Text("евродоллары", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("$balance", color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 36.sp)
                    Text(" €$", color = MB10Colors.inkSecondary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                }
            }
        }

        Spacer(Modifier.height(14.dp))
        AppButton(
            if (sending) "Скрыть" else "Отправить",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Primary,
            onClick = { sending = !sending }
        )

        if (sending) {
            Spacer(Modifier.height(14.dp))
            SendTransactionPanel(
                contacts = contacts,
                onlineKeys = onlineKeys,
                transactions = transactions,
                onSend = { contact, id, amount, memo ->
                    val payload = Mb10QrCodec.transactionSignaturePayload(id, identity.publicKeyB64, amount, memo)
                    val signature = IdentityManager.sign(context, payload)
                    val tx = Mb10Qr.Transaction(id, identity.publicKeyB64, amount, memo, signature)
                    val peer = onlinePeers.find { it.pubKeyB64 == contact.publicKeyB64 }
                    scope.launch {
                        TransactionStore.recordOutgoingPending(context, tx, contact.publicKeyB64)
                        ChatStore.sendDirect(context, identity, contact.publicKeyB64, peer, Mb10QrCodec.encodeTransaction(tx))
                    }
                },
                onCancel = { id -> scope.launch { TransactionStore.cancelOutgoing(context, id) } }
            )
        }

        Spacer(Modifier.height(20.dp))
        SectionLabel("Операции")
        if (transactions.isEmpty()) {
            EmptyState("Ещё не было ни одной транзакции.")
        } else {
            Column {
                transactions.forEachIndexed { index, tx ->
                    TxRow(
                        tx = tx,
                        counterpartyName = contactsByKey[tx.counterpartyPubKeyB64]?.callsign,
                        onCancelPending = { scope.launch { TransactionStore.cancelOutgoing(context, tx.id) } }
                    )
                    if (index != transactions.lastIndex) DottedDivider()
                }
            }
        }
    }
}

private data class SentPayment(val id: String, val contact: Mb10Qr.Contact, val amount: Long, val memo: String)

@Composable
private fun SendTransactionPanel(
    contacts: List<Mb10Qr.Contact>,
    onlineKeys: Set<String>,
    transactions: List<TransactionEntity>,
    onSend: (contact: Mb10Qr.Contact, id: String, amount: Long, memo: String) -> Unit,
    onCancel: (id: String) -> Unit
) {
    var selectedContact by remember { mutableStateOf<Mb10Qr.Contact?>(null) }
    var sent by remember { mutableStateOf<SentPayment?>(null) }

    ChamferedPanel(
        borderColor = MB10Colors.borderMuted,
        fillColor = MB10Colors.surfaceRaised,
        cut = 6.dp,
        contentPadding = 14.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        val activeSent = sent
        when {
            activeSent != null -> {
                val status = transactions.find { it.id == activeSent.id }?.status
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "Отправлено → ${activeSent.contact.callsign}",
                        color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp, textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "${activeSent.amount} €$" + if (activeSent.memo.isNotBlank()) " · ${activeSent.memo}" else "",
                        color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 20.sp
                    )
                    Spacer(Modifier.height(10.dp))
                    StatusChip(
                        if (status == TransactionStatus.CONFIRMED) "подтверждено" else "ожидает подтверждения",
                        tone = if (status == TransactionStatus.CONFIRMED) ChipTone.Action else ChipTone.Neutral
                    )
                    Spacer(Modifier.height(12.dp))
                    if (status == TransactionStatus.CONFIRMED) {
                        AppButton(
                            "Новый платёж", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Primary,
                            onClick = { sent = null; selectedContact = null }
                        )
                    } else {
                        Text(
                            "Ждём, пока получатель примет перевод в чате.",
                            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 11.5.sp, lineHeight = 15.sp,
                            textAlign = TextAlign.Center
                        )
                        Spacer(Modifier.height(10.dp))
                        AppButton(
                            "Отменить платёж", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Danger,
                            onClick = { onCancel(activeSent.id); sent = null; selectedContact = null }
                        )
                    }
                }
            }
            selectedContact == null -> {
                Column {
                    Text("Кому отправить", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
                    Spacer(Modifier.height(10.dp))
                    if (contacts.isEmpty()) {
                        EmptyState("Нет добавленных контактов — сначала отсканируйте QR-код игрока в Профиле.")
                    } else {
                        contacts.forEachIndexed { index, c ->
                            ListRow(
                                onClick = { selectedContact = c },
                                leading = { HexBullet(if (c.publicKeyB64 in onlineKeys) MB10Colors.inkPrimary else MB10Colors.inkTertiary, size = 7.dp) }
                            ) {
                                Text(c.callsign, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                                Text(c.faction, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
                            }
                            if (index != contacts.lastIndex) DottedDivider()
                        }
                    }
                }
            }
            else -> {
                val contact = selectedContact!!
                var amountText by remember { mutableStateOf("") }
                var memoText by remember { mutableStateOf("") }
                val amountValid = amountText.toLongOrNull()?.let { it > 0 } ?: false
                val showError = amountText.isNotEmpty() && !amountValid

                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Кому: ", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
                        Text(
                            contact.callsign, color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono,
                            fontSize = 11.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f)
                        )
                        Text(
                            "Сменить", color = MB10Colors.accentAction, fontFamily = JetBrainsMono, fontSize = 10.sp,
                            modifier = Modifier.clickable { selectedContact = null }
                        )
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(
                        "Сумма списывается с вашего баланса сразу — как передать наличные из рук в руки. Перевод уйдёт получателю сообщением в чат — до его подтверждения платёж ещё можно отменить.",
                        color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp
                    )
                    Spacer(Modifier.height(10.dp))
                    AmountField(value = amountText, onValueChange = { amountText = it }, modifier = Modifier.fillMaxWidth())
                    if (showError) {
                        Spacer(Modifier.height(4.dp))
                        Text("Введите сумму больше нуля", color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 10.sp)
                    }
                    Spacer(Modifier.height(8.dp))
                    AppTextField(
                        value = memoText,
                        onValueChange = { memoText = it },
                        placeholder = "За что (необязательно)",
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(10.dp))
                    AppButton(
                        "Отправить",
                        modifier = Modifier.fillMaxWidth(),
                        variant = ButtonVariant.Primary,
                        enabled = amountValid,
                        onClick = {
                            val id = UUID.randomUUID().toString()
                            val amount = amountText.toLong()
                            onSend(contact, id, amount, memoText)
                            sent = SentPayment(id, contact, amount, memoText)
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun TxRow(tx: TransactionEntity, counterpartyName: String?, onCancelPending: () -> Unit) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val pending = tx.status == TransactionStatus.PENDING
    ListRow(
        trailing = {
            val amountText = (if (tx.amount > 0) "+" else "") + tx.amount
            Text(
                amountText,
                color = if (tx.amount > 0) MB10Colors.accentAction else MB10Colors.inkSecondary,
                fontFamily = JetBrainsMono,
                fontSize = 13.sp
            )
        }
    ) {
        val title = tx.memo.ifBlank { if (tx.amount > 0) "Входящий платёж" else "Платёж" }
        Text(title, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
        val timeText = timeFormat.format(tx.timestamp)
        val fromText = if (tx.counterpartyPubKeyB64.isEmpty()) {
            null
        } else {
            val label = counterpartyName ?: (tx.counterpartyPubKeyB64.take(8) + "…")
            if (tx.amount > 0) " · от $label" else " · → $label"
        }
        val statusText = if (pending) " · ожидает подтверждения" else ""
        Text(
            timeText + (fromText ?: "") + statusText,
            color = if (pending) MB10Colors.accentAction else MB10Colors.inkSecondary,
            fontFamily = JetBrainsMono, fontSize = 10.sp
        )
        if (pending) {
            Text(
                "Отменить",
                color = MB10Colors.accentDanger,
                fontFamily = JetBrainsMono,
                fontSize = 10.sp,
                modifier = Modifier.clickable(onClick = onCancelPending).padding(top = 2.dp)
            )
        }
    }
}
