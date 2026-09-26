package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.breach.BreachResult
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.DaemonPicker
import com.megablok10.app.breach.HackCell
import com.megablok10.app.breach.ResultOverlay
import com.megablok10.app.breach.RewardOutcome
import com.megablok10.app.breach.Tier
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsBreach
import org.junit.Rule
import org.junit.Test

/** M4.5 плана миграции: экран взлома (тема Breach) — DaemonPicker/HackCell/ResultOverlay на новых токенах. */
class BreachScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsBreach) {
                Box(Modifier.background(MbColorsBreach.bg).padding(10.dp)) {
                    Column { content() }
                }
            }
        }
    }

    private val daemons = listOf(
        Daemon("d1", "Black Curtain", listOf("7A", "BD", "55"), tier = Tier.HARD, effect = DaemonEffect.BLACKOUT),
        Daemon("d2", "Cipher Key", listOf("7A", "E9"), tier = Tier.HARD, effect = DaemonEffect.DECRYPT),
        Daemon("d3", "Deep Miner", listOf("E9", "FF"), tier = Tier.HARD, effect = DaemonEffect.MINER),
    )

    @Test
    fun hackCells() = snap("breach_hack_cells") {
        Row {
            HackCell(56.dp, "1C", isSelected = false, orderLabel = null, isSelectable = false, onClick = {})
            HackCell(56.dp, "7A", isSelected = false, orderLabel = null, isSelectable = true, onClick = {})
            HackCell(56.dp, "BD", isSelected = true, orderLabel = "1", isSelectable = false, onClick = {})
            HackCell(56.dp, "✕✕", isSelected = false, orderLabel = null, isSelectable = false, onClick = {})
        }
    }

    @Test
    fun daemonPicker() = snap("breach_daemon_picker") {
        DaemonPicker(daemons = daemons, chosen = setOf("d1", "d3"), remainingBuffer = 1, onToggle = {})
    }

    @Test
    fun resultSuccess() = snap("breach_result_success") {
        Box(Modifier.height(500.dp)) {
            ResultOverlay(
                result = BreachResult(daemons.take(2), setOf("d1", "d2")),
                failMessage = "", rewardOutcome = RewardOutcome(60, listOf("Спецификация К-7"), emptyList(), false, setOf(DaemonEffect.BLACKOUT)),
                secAlertStatus = "подавлен (Blackout)", actionLabel = "Новый контейнер", onAction = {}
            )
        }
    }

    @Test
    fun resultFail() = snap("breach_result_fail") {
        Box(Modifier.height(420.dp)) {
            ResultOverlay(
                result = BreachResult(daemons.take(2), emptySet()),
                failMessage = "СБ зафиксировала попытку. Контейнер заблокирован до конца этого акта.",
                rewardOutcome = null, secAlertStatus = "отправлен фракции «Arasaka»", actionLabel = "Новый контейнер", onAction = {}
            )
        }
    }
}
