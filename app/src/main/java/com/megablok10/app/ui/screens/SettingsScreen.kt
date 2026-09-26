package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.megablok10.app.di.announcementsViewModel
import com.megablok10.app.di.settingsViewModel
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.sound.BreachSfx
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDialogTone
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbFormRow
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbToggle
import com.megablok10.app.ui.theme.MbTypography

/**
 * M4.6 плана миграции: вкладка «Настройки» — уведомления, сообщения мастера, опасная зона (сброс сессии). Мешь-сеть,
 * очередь синка, журнал и адрес коллектора переехали в NetworkScreen (вкладка «Сеть») — та же логика, но раньше это был
 * один длинный список.
 */
@Composable
fun SettingsScreen(onResetIdentity: () -> Unit) {
    val context = LocalContext.current
    val c = LocalMbColors.current
    var pushEnabled by remember { mutableStateOf(true) }
    var soundEnabled by remember { mutableStateOf(false) }
    var confirmingReset by remember { mutableStateOf(false) }
    val settings = appViewModel { settingsViewModel() }
    // Как в мессенджерах: выключил — свои отчёты не уходят и чужое «прочитано» не видно (docs/refactor-plan.md, D4).
    val readReceipts by settings.readReceiptsEnabled.collectAsStateWithLifecycle()
    var breachSfx by remember { mutableStateOf(BreachSfx.isEnabled(context)) }
    val announcements by appViewModel { announcementsViewModel() }.items.collectAsStateWithLifecycle()

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = MbDimens.blockGap),
        verticalArrangement = Arrangement.spacedBy(MbDimens.rowGap)
    ) {
        MbSectionTitle("Уведомления")
        MbFormRow("Push-уведомления") { MbToggle(pushEnabled, { pushEnabled = it }) }
        MbFormRow("Звук при новом сообщении") { MbToggle(soundEnabled, { soundEnabled = it }) }
        MbFormRow("Отчёты о прочтении") { MbToggle(readReceipts, { settings.setReadReceipts(it) }) }
        MbFormRow("Звуки взлома") { MbToggle(breachSfx, { breachSfx = it; BreachSfx.setEnabled(context, it) }) }

        if (announcements.isNotEmpty()) {
            MbSectionTitle("Сообщения мастера", meta = announcements.size.toString())
            val format = remember { java.text.SimpleDateFormat("dd.MM HH:mm", java.util.Locale.getDefault()) }
            announcements.take(10).forEach { a ->
                MbListItem(title = a.text, sub = format.format(java.util.Date(a.receivedAt)), titleWrap = true, subWrap = true, plate = true)
            }
        }

        MbSectionTitle("Опасная зона")
        Text("Смена фракции — по решению мастера, вручную вне приложения.", style = MbTypography.meta, color = c.ink2)
        MbButton(
            "Сбросить сессию персонажа", kind = MbButtonKind.Danger, modifier = Modifier.fillMaxWidth(),
            onClick = { confirmingReset = true; Mb10Log.event("Settings", "reset_dialog_opened") }
        )
    }

    if (confirmingReset) {
        MbDialog(
            onDismissRequest = { confirmingReset = false },
            icon = MbIcons.Reset,
            title = "Сбросить сессию персонажа?",
            tone = MbDialogTone.Danger,
            actions = listOf(
                MbDialogAction("Сбросить", MbButtonKind.Danger) { confirmingReset = false; onResetIdentity() },
                MbDialogAction("Отмена", MbButtonKind.Quiet) { confirmingReset = false }
            )
        ) {
            Text("Ключевая пара, позывной и фракция этого устройства будут удалены безвозвратно. Отменить нельзя.")
        }
    }
}
