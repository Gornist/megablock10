package com.megablok10.app.ui.screens

import android.widget.Toast
import androidx.compose.foundation.Image
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.data.TransactionEntity
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

    val scanTransaction = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.Transaction -> scope.launch {
                val credited = TransactionStore.recordIncoming(context, identity.publicKeyB64, qr)
                val message = if (credited) "Зачислено ${qr.amount} €$" else "QR транзакции недействителен или уже отсканирован"
                Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
            }
            else -> Toast.makeText(context, "Это не QR-код транзакции", Toast.LENGTH_SHORT).show()
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
                if (sending) "Отменить" else "Отправить",
                modifier = Modifier.weight(1f),
                accentColor = MB10Colors.yellow,
                onClick = {
                    sending = !sending
                    pendingTx = null
                }
            )
            OutlineButton("Получить (скан)", modifier = Modifier.weight(1f), borderColor = MB10Colors.inkFaint, onClick = scanTransaction)
        }

        if (sending) {
            Spacer(Modifier.height(14.dp))
            SendTransactionPanel(
                pendingTx = pendingTx,
                onGenerate = { amount, memo ->
                    val id = UUID.randomUUID().toString()
                    val payload = Mb10QrCodec.transactionSignaturePayload(id, identity.publicKeyB64, amount, memo)
                    val signature = IdentityManager.sign(context, payload)
                    val tx = Mb10Qr.Transaction(id, identity.publicKeyB64, amount, memo, signature)
                    scope.launch { TransactionStore.recordOutgoing(context, tx) }
                    pendingTx = tx
                },
                onDone = {
                    sending = false
                    pendingTx = null
                }
            )
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
                    TxRow(tx, contactsByKey[tx.counterpartyPubKeyB64]?.callsign)
                    if (index != transactions.lastIndex) DottedDivider()
                }
            }
        }
    }
}

@Composable
private fun SendTransactionPanel(
    pendingTx: Mb10Qr.Transaction?,
    onGenerate: (amount: Long, memo: String) -> Unit,
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
                    "Сумма списывается с вашего баланса сразу — как передать наличные из рук в руки. Покажите QR тому, кто получает деньги.",
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
                    accentColor = MB10Colors.yellow,
                    enabled = amountValid,
                    onClick = { onGenerate(amountText.toLong(), memoText) }
                )
            }
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "Покажите этот QR получателю платежа",
                    color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp
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
                OutlineButton("Готово", modifier = Modifier.fillMaxWidth(), onClick = onDone)
            }
        }
    }
}

@Composable
private fun TxRow(tx: TransactionEntity, counterpartyName: String?) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
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
            Text(timeText + (fromText ?: ""), color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
        }
        val amountText = (if (tx.amount > 0) "+" else "") + tx.amount
        Text(
            amountText,
            color = if (tx.amount > 0) MB10Colors.yellow else MB10Colors.inkMuted,
            fontFamily = JetBrainsMono,
            fontSize = 13.sp
        )
    }
}
