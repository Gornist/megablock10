package com.megablok10.app.ui.screens

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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors

private data class DemoTx(val name: String, val time: String, val amount: Int)

/**
 * Демо-данные из HTML-макета — реальная экономика (подписанные
 * транзакции) появится на соответствующем этапе roadmap. Баланс здесь
 * ничего не вычисляет, просто рисует layout.
 */
private val demoTransactions = listOf(
    DemoTx("Антидот — контрабандист", "21:10", -350),
    DemoTx("Информация — рынок", "20:52", -80),
    DemoTx("Оплата за охрану периметра", "20:15", 220)
)

@Composable
fun WalletScreen() {
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
                    Text("1 240", color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 36.sp)
                    Text(" €$", color = MB10Colors.inkMuted, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Операции")
        Column {
            demoTransactions.forEachIndexed { index, tx ->
                TxRow(tx)
                if (index != demoTransactions.lastIndex) DottedDivider()
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
        HexBullet(MB10Colors.inkMuted, size = 8.dp)
        Spacer(Modifier.width(6.dp))
        Text(text, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
    }
}

@Composable
private fun TxRow(tx: DemoTx) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 9.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(tx.name, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
            Text(tx.time, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
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
