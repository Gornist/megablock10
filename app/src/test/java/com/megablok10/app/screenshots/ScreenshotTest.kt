package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.breach.BreachResult
import com.megablok10.app.breach.BufferPanel
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.DaemonPicker
import com.megablok10.app.breach.HackCell
import com.megablok10.app.breach.ResultOverlay
import com.megablok10.app.breach.RewardOutcome
import com.megablok10.app.breach.TerminalFrame
import com.megablok10.app.breach.Tier
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppToggle
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChipTone
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.ScanFab
import com.megablok10.app.ui.theme.SegmentedTabs
import com.megablok10.app.ui.theme.StatusChip
import androidx.compose.material3.Text
import org.junit.Rule
import org.junit.Test

/**
 * Скриншот-тесты интерфейса на JVM (Paparazzi) — без эмулятора, секунды вместо минут. Эталоны лежат в app/src/test/snapshots/images.
 *   ./gradlew verifyPaparazziDebug   — сравнить с эталонами (это делает CI и scripts/check.sh)
 *   ./gradlew recordPaparazziDebug   — осознанно обновить эталоны после намеренной правки интерфейса
 * Допуск 0,5 % пикселей: сглаживание шрифтов на macOS и Linux чуть различается.
 */
class ScreenshotTest {
    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false),
        theme = "android:Theme.Material.NoActionBar",
        maxPercentDifference = 0.5
    )

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            MaterialTheme(colorScheme = darkColorScheme(primary = MB10Colors.accentAction, background = MB10Colors.surfaceBase, surface = MB10Colors.surfaceRaised)) {
                Box(Modifier.background(MB10Colors.surfaceBase).padding(12.dp)) { content() }
            }
        }
    }

    private val daemons = listOf(
        Daemon("d1", "Black Curtain", listOf("7A", "BD", "55"), tier = Tier.HARD, effect = DaemonEffect.BLACKOUT),
        Daemon("d2", "Cipher Key", listOf("7A", "E9"), tier = Tier.HARD, effect = DaemonEffect.DECRYPT),
        Daemon("d3", "Deep Miner", listOf("E9", "FF"), tier = Tier.HARD, effect = DaemonEffect.MINER),
    )

    @Test fun designSystem() = snap("design_system") {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AppButton("Primary", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Primary, onClick = {})
            AppButton("Netrun", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Netrun, onClick = {})
            AppButton("Secondary dense", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, dense = true, onClick = {})
            AppButton("Danger dense", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Danger, dense = true, onClick = {})
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusChip("нейтрально"); StatusChip("действие", ChipTone.Action); StatusChip("опасно", ChipTone.Danger); StatusChip("нетран", ChipTone.Netrun)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { AppToggle(true, {}); AppToggle(false, {}) }
            SegmentedTabs(listOf("Демоны", "Шарды"), selected = 0, onSelect = {})
            ListRow(trailing = { StatusChip("3 яч.") }) {
                Text("Строка списка", color = MB10Colors.inkPrimary)
                Text("вторая строка", color = MB10Colors.inkSecondary)
            }
            EmptyState("Пока пусто. Отсканируйте метку.")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { ScanFab(onClick = {}) }
        }
    }

    @Test fun breachBufferAndCells() = snap("breach_buffer_cells") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            BufferPanel(codes = listOf("7A", "BD", "55"), size = 9)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                HackCell(56.dp, "1C", isSelected = false, orderLabel = null, isSelectable = false, onClick = {})
                HackCell(56.dp, "7A", isSelected = false, orderLabel = null, isSelectable = true, onClick = {})
                HackCell(56.dp, "BD", isSelected = true, orderLabel = "1", isSelectable = false, onClick = {})
                HackCell(56.dp, "✕✕", isSelected = false, orderLabel = null, isSelectable = false, onClick = {})
            }
        }
    }

    @Test fun daemonPicker() = snap("daemon_picker") {
        Column {
            BufferPanel(codes = listOf("7A", "BD", "55", "E9", "FF"), size = 6)
            Spacer(Modifier.height(6.dp))
            DaemonPicker(daemons = daemons, chosen = setOf("d1", "d3"), remainingBuffer = 1, onToggle = {})
        }
    }

    @Test fun breachResultSuccess() = snap("breach_result_success") {
        TerminalFrame { Text("сетка под затемнением", color = MB10Colors.inkSecondary) }
        Box(Modifier.height(420.dp)) {
            ResultOverlay(
                result = BreachResult(daemons.take(2), setOf("d1", "d2")),
                failMessage = "", rewardOutcome = RewardOutcome(60, listOf("Спецификация К-7"), emptyList(), false, setOf(DaemonEffect.BLACKOUT)),
                secAlertStatus = "подавлен (Blackout)", actionLabel = "Новый контейнер", onAction = {}
            )
        }
    }

    @Test fun breachResultFail() = snap("breach_result_fail") {
        Box(Modifier.height(320.dp)) {
            ResultOverlay(
                result = BreachResult(daemons.take(2), emptySet()),
                failMessage = "СБ зафиксировала попытку. Контейнер заблокирован до конца этого акта.",
                rewardOutcome = null, secAlertStatus = "отправлен фракции «Arasaka»", actionLabel = "Новый контейнер", onAction = {}
            )
        }
    }
}
