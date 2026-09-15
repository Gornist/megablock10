package com.megablok10.app.ui.screens

import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.generateQrBitmap
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OutlineButton
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

@Composable
fun WalletScreen(identity: Identity) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val balance by TransactionStore.observeBalance(context).collectAsState(initial = 0L)
    val transactions by TransactionStore.observeAll(context).collectAsState(initial = emptyList())
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val contactsByKey = remember(contacts) { contacts.associateBy { it.publicKeyB64 } }

    var sending by remember { mutableStateOf(false) }
    var pendingTx by remember { mutableStateOf<Mb10Qr.Transaction?>(null) }
    var confirmed by remember { mutableStateOf(false) }
    var incomingReceipt by remember { mutableStateOf<Mb10Qr.Receipt?>(null) }

    fun resetSendPanel() {
        sending = false
        pendingTx = null
        confirmed = false
    }

    val scanTransaction = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.Transaction -> scope.launch {
                val credited = TransactionStore.recordIncoming(context, identity.publicKeyB64, qr)
                if (credited) {
                    incomingReceipt = TransactionStore.buildReceipt(context, identity, qr.id)
                    Toast.makeText(context, "Зачислено ${qr.amount} €$ — покажите QR-подтверждение отправителю", Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(context, "QR транзакции недействителен или уже отсканирован", Toast.LENGTH_SHORT).show()
                }
            }
            else -> Toast.makeText(context, "Это не QR-код транзакции", Toast.LENGTH_SHORT).show()
        }
    }

    val scanReceipt = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.Receipt -> {
                val tx = pendingTx
                if (tx == null) {
                    Toast.makeText(context, "Нет платежа, ожидающего подтверждения", Toast.LENGTH_SHORT).show()
                } else {
                    scope.launch {
                        val ok = TransactionStore.verifyAndConfirmReceipt(context, tx.id, qr)
                        if (ok) {
                            confirmed = true
                            Toast.makeText(context, "Получатель подтвердил получение", Toast.LENGTH_SHORT).show()
                        } else {
                            Toast.makeText(context, "Это подтверждение не подходит к этому платежу", Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
            else -> Toast.makeText(context, "Это не QR-код подтверждения", Toast.LENGTH_SHORT).show()
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionLabel("Баланс")
        ChamferedPanel(
            borderColor = MB10Colors.inkFaint,
            fillColor = MB10Colors.bg2,
            cut = 10.dp,
            doubleCorner = true,
            contentPadding = 16.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column {
                Text("евродоллары", color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("$balance", color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 36.sp)
                    Text(" €$", color = MB10Colors.inkMuted, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                }
            }
        }

        Spacer(Modifier.height(14.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlineButton(
                if (sending) "Скрыть" else "Отправить",
                modifier = Modifier.weight(1f),
                accentColor = MB10Colors.accentPrimary,
                onClick = { sending = !sending }
            )
            OutlineButton("Получить (скан)", modifier = Modifier.weight(1f), borderColor = MB10Colors.inkFaint, onClick = scanTransaction)
        }

        if (sending) {
            Spacer(Modifier.height(14.dp))
            SendTransactionPanel(
                pendingTx = pendingTx,
                confirmed = confirmed,
                onGenerate = { amount, memo ->
                    val id = UUID.randomUUID().toString()
                    val payload = Mb10QrCodec.transactionSignaturePayload(id, identity.publicKeyB64, amount, memo)
                    val signature = IdentityManager.sign(context, payload)
                    val tx = Mb10Qr.Transaction(id, identity.publicKeyB64, amount, memo, signature)
                    scope.launch { TransactionStore.recordOutgoingPending(context, tx) }
                    pendingTx = tx
                },
                onCancel = {
                    val tx = pendingTx
                    if (tx != null) scope.launch { TransactionStore.cancelOutgoing(context, tx.id) }
                    resetSendPanel()
                },
                onScanReceipt = scanReceipt,
                onDone = { resetSendPanel() }
            )
        }

        incomingReceipt?.let { receipt ->
            Spacer(Modifier.height(14.dp))
            ReceiptPanel(receipt = receipt, onDone = { incomingReceipt = null })
        }

        Spacer(Modifier.height(20.dp))
        SectionLabel("Операции")
        if (transactions.isEmpty()) {
            Text(
                "Ещё не было ни одной транзакции.",
                color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp
            )
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

@Composable
private fun SendTransactionPanel(
    pendingTx: Mb10Qr.Transaction?,
    confirmed: Boolean,
    onGenerate: (amount: Long, memo: String) -> Unit,
    onCancel: () -> Unit,
    onScanReceipt: () -> Unit,
    onDone: () -> Unit
) {
    ChamferedPanel(
        borderColor = MB10Colors.inkFaint,
        fillColor = MB10Colors.bg1,
        cut = 6.dp,
        contentPadding = 14.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        if (pendingTx == null) {
            var amountText by remember { mutableStateOf("") }
            var memoText by remember { mutableStateOf("") }
            val amountValid = amountText.toLongOrNull()?.let { it > 0 } ?: false

            Column {
                Text(
                    "Сумма списывается с вашего баланса сразу — как передать наличные из рук в руки. Покажите QR тому, кто получает деньги, а затем отсканируйте его QR-подтверждение — до этого платёж ещё можно отменить.",
                    color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp
                )
                Spacer(Modifier.height(10.dp))
                TextField(
                    value = amountText,
                    onValueChange = { amountText = it.filter(Char::isDigit) },
                    placeholder = { Text("Сумма, €$", color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                TextField(
                    value = memoText,
                    onValueChange = { memoText = it },
                    placeholder = { Text("За что (необязательно)", color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(10.dp))
                OutlineButton(
                    "Сгенерировать QR",
                    modifier = Modifier.fillMaxWidth(),
                    accentColor = MB10Colors.accentPrimary,
                    enabled = amountValid,
                    onClick = { onGenerate(amountText.toLong(), memoText) }
                )
            }
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    if (confirmed) "Получатель подтвердил получение" else "Покажите этот QR получателю платежа",
                    color = if (confirmed) MB10Colors.accentPrimary else MB10Colors.ink0,
                    fontFamily = IBMPlexSans, fontSize = 13.sp, textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(10.dp))
                val bitmap = remember(pendingTx.id) { generateQrBitmap(Mb10QrCodec.encodeTransaction(pendingTx)) }
                Image(bitmap = bitmap.asImageBitmap(), contentDescription = "QR транзакции", modifier = Modifier.size(200.dp))
                Spacer(Modifier.height(6.dp))
                Text(
                    "${pendingTx.amount} €$" + if (pendingTx.memo.isNotBlank()) " · ${pendingTx.memo}" else "",
                    color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 11.sp
                )
                Spacer(Modifier.height(12.dp))
                if (confirmed) {
                    OutlineButton("Готово", modifier = Modifier.fillMaxWidth(), onClick = onDone)
                } else {
                    Text(
                        "Ожидает подтверждения — отсканируйте QR-чек получателя, чтобы зафиксировать платёж.",
                        color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 11.5.sp, lineHeight = 15.sp,
                        textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(10.dp))
                    OutlineButton(
                        "Подтвердить получение (скан)",
                        modifier = Modifier.fillMaxWidth(),
                        accentColor = MB10Colors.accentPrimary,
                        onClick = onScanReceipt
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlineButton(
                        "Отменить платёж",
                        modifier = Modifier.fillMaxWidth(),
                        accentColor = MB10Colors.danger,
                        onClick = onCancel
                    )
                }
            }
        }
    }
}

@Composable
private fun ReceiptPanel(receipt: Mb10Qr.Receipt, onDone: () -> Unit) {
    ChamferedPanel(
        borderColor = MB10Colors.accentPrimary,
        fillColor = MB10Colors.bg1,
        cut = 6.dp,
        contentPadding = 14.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Text(
                "Покажите этот QR отправителю для подтверждения",
                color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp, textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(10.dp))
            val bitmap = remember(receipt.id) { generateQrBitmap(Mb10QrCodec.encodeReceipt(receipt)) }
            Image(bitmap = bitmap.asImageBitmap(), contentDescription = "QR подтверждения", modifier = Modifier.size(200.dp))
            Spacer(Modifier.height(12.dp))
            OutlineButton("Готово", modifier = Modifier.fillMaxWidth(), onClick = onDone)
        }
    }
}

@Composable
private fun TxRow(tx: TransactionEntity, counterpartyName: String?, onCancelPending: () -> Unit) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val pending = tx.status == TransactionStatus.PENDING
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 9.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            val title = tx.memo.ifBlank { if (tx.amount > 0) "Входящий платёж" else "Платёж" }
            Text(title, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
            val timeText = timeFormat.format(tx.timestamp)
            val fromText = when {
                tx.amount <= 0 -> null
                counterpartyName != null -> " · от $counterpartyName"
                tx.counterpartyPubKeyB64.isNotEmpty() -> " · от ${tx.counterpartyPubKeyB64.take(8)}…"
                else -> null
            }
            val statusText = if (pending) " · ожидает подтверждения" else ""
            Text(
                timeText + (fromText ?: "") + statusText,
                color = if (pending) MB10Colors.accentPrimary else MB10Colors.inkMuted,
                fontFamily = JetBrainsMono, fontSize = 10.sp
            )
            if (pending) {
                Text(
                    "Отменить",
                    color = MB10Colors.danger,
                    fontFamily = JetBrainsMono,
                    fontSize = 10.sp,
                    modifier = Modifier.clickable(onClick = onCancelPending).padding(top = 2.dp)
                )
            }
        }
        val amountText = (if (tx.amount > 0) "+" else "") + tx.amount
        Text(
            amountText,
            color = if (tx.amount > 0) MB10Colors.accentPrimary else MB10Colors.inkMuted,
            fontFamily = JetBrainsMono,
            fontSize = 13.sp
        )
    }
}
