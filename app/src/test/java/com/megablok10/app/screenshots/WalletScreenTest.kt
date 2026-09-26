package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.ui.screens.TxRow
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbAmountField
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbTile
import com.megablok10.app.ui.theme.MbTileTone
import org.junit.Rule
import org.junit.Test

/** M4.3 плана миграции: экран «Финансы» — фейковые данные (TxRow — internal в WalletScreen.kt). */
class WalletScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg).padding(10.dp)) {
                    Column { content() }
                }
            }
        }
    }

    @Test
    fun balanceTile() = snap("wallet_balance") {
        MbTile(
            "Баланс", value = "1 240", valueUnit = "€$", tone = MbTileTone.Money, big = true,
            subItems = listOf("+335 за сутки", "−170 отправлено")
        )
    }

    @Test
    fun amountField() = snap("wallet_amount_field") {
        MbAmountField(value = "120", onValueChange = {})
    }

    private fun tx(id: String, counterparty: String, amount: Long, memo: String, ts: Long, status: String) =
        TransactionEntity(id = id, counterpartyPubKeyB64 = counterparty, amount = amount, memo = memo, timestamp = ts, status = status)

    @Test
    fun operationsList() = snap("wallet_operations") {
        TxRow(tx("1", "kisa", 300, "«долг за крышу»", 1L, TransactionStatus.CONFIRMED), counterpartyName = "Киса", onCancelPending = {})
        TxRow(tx("2", "lom", -120, "«за патроны»", 2L, TransactionStatus.PENDING), counterpartyName = "Лом", onCancelPending = {})
        TxRow(tx("3", "vobla", -50, "", 3L, TransactionStatus.DELIVERED), counterpartyName = "Вобла", onCancelPending = {})
    }

    @Test
    fun emptyState() = snap("wallet_empty") {
        MbEmptyState(MbIcons.Wallet, "Пока пусто", "Ещё не было ни одной транзакции.")
    }
}
