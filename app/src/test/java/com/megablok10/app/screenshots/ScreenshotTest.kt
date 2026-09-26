package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
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
 * Скриншот-тесты старой дизайн-системы (то, что ещё не перенесено на Mb*-компоненты) на JVM (Paparazzi) — без эмулятора,
 * секунды вместо минут. Взлом (BufferPanel/DaemonPicker/HackCell/ResultOverlay) перенесён — его каталог теперь в
 * BreachScreenTest.kt (M4.5 плана миграции). Эталоны лежат в app/src/test/snapshots/images.
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
}
