package com.megablok10.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppDialog
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.sound.BreachSfx
import com.megablok10.app.ui.theme.AppToggle
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.ChipTone
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.ui.theme.StatusChip

@Composable
fun SettingsScreen(onResetIdentity: () -> Unit) {
    val context = LocalContext.current
    var pushEnabled by remember { mutableStateOf(true) }
    var soundEnabled by remember { mutableStateOf(false) }
    var confirmingReset by remember { mutableStateOf(false) }
    val onlinePeers by PresenceService.peers.collectAsState()
    var collectorUrl by remember { mutableStateOf(CollectorSettings.baseUrl(context) ?: "") }
    val announcements by AnnouncementStore.items.collectAsState()
    var gameSecret by remember { mutableStateOf(CollectorSettings.gameSecret(context) ?: "") }
    val pendingChanges by Mb10Database.get(context).pendingChangeRecordDao().observeCount().collectAsState(initial = 0)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
        SectionLabel("Приложение")
        ToggleRow("Push-уведомления", pushEnabled) { pushEnabled = it }
        Spacer(Modifier.height(6.dp))
        ToggleRow("Звук при новом сообщении", soundEnabled) { soundEnabled = it }
        Spacer(Modifier.height(10.dp))
        var breachSfx by remember { mutableStateOf(BreachSfx.isEnabled(context)) }
        ToggleRow("Звуки взлома", breachSfx) { breachSfx = it; BreachSfx.setEnabled(context, it) }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Сеть и данные")
        ListRow(trailing = { StatusChip("${onlinePeers.size} в сети", tone = ChipTone.Neutral) }) {
            Text("Мешь-сеть", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
            Text("устройства рядом обнаруживаются через NSD", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }

        Spacer(Modifier.height(16.dp))
        if (announcements.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            SectionLabel("Сообщения мастера")
            val format = remember { java.text.SimpleDateFormat("dd.MM HH:mm", java.util.Locale.getDefault()) }
            announcements.take(10).forEach { a ->
                ListRow {
                    Text(a.text, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    Text(format.format(java.util.Date(a.receivedAt)), color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
                }
                Spacer(Modifier.height(6.dp))
            }
        }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Мастерский коллектор")
        var collectorHelp by remember { mutableStateOf(false) }
        Text(
            if (collectorHelp) "Скрыть подсказки" else "Подробнее",
            color = MB10Colors.accentAction, fontFamily = JetBrainsMono, fontSize = 11.sp,
            modifier = Modifier.clickable { collectorHelp = !collectorHelp }.padding(vertical = 4.dp)
        )
        if (collectorHelp) {
            Text(
                "Адрес ноутбука мастера в игровой сети — сюда уходит история изменений для дашборда. Пусто — ничего не отправляется, игра работает как обычно. " +
                    "Код игры нужен, если мастер задал его на сервере (GAME_SECRET): без него запросы к коллектору будут отклонены.",
                color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp
            )
        }
        Spacer(Modifier.height(6.dp))
        ListRow(
            trailing = { StatusChip(if (pendingChanges > 0) "$pendingChanges ожидает" else "всё отправлено", tone = if (pendingChanges > 0) ChipTone.Neutral else ChipTone.Action) }
        ) {
            Text("Очередь синка", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
            Text("записи, ещё не подтверждённые коллектором", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(8.dp))
        AppTextField(
            value = collectorUrl,
            onValueChange = { collectorUrl = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = "http://192.168.1.10:8080"
        )
        Spacer(Modifier.height(8.dp))
        AppButton(
            "Сохранить адрес коллектора",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Secondary,
            onClick = { CollectorSettings.setBaseUrl(context, collectorUrl.ifBlank { null }) }
        )
        Spacer(Modifier.height(8.dp))
        AppTextField(
            value = gameSecret,
            onValueChange = { gameSecret = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = "код игры"
        )
        Spacer(Modifier.height(8.dp))
        AppButton(
            "Сохранить код игры",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Secondary,
            onClick = { CollectorSettings.setGameSecret(context, gameSecret.ifBlank { null }) }
        )

        // Необратимое действие — отдельным блоком внизу, чтобы не нажать по соседству с обычными кнопками.
        Spacer(Modifier.height(28.dp))
        SectionLabel("Опасная зона", color = MB10Colors.accentDanger)
        Text(
            "Смена фракции — по решению мастера, вручную вне приложения.",
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp
        )
        Spacer(Modifier.height(8.dp))
        AppButton("Сбросить сессию персонажа", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Danger, dense = true, onClick = { confirmingReset = true })
        Spacer(Modifier.height(16.dp))
    }

    if (confirmingReset) {
        AppDialog(
            onDismissRequest = { confirmingReset = false },
            title = "Сбросить сессию персонажа?",
            body = "Ключевая пара, позывной и фракция этого устройства будут удалены безвозвратно. Отменить нельзя.",
            confirmText = "Сбросить",
            onConfirm = { confirmingReset = false; onResetIdentity() }
        )
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    ChamferedSurface(
        borderColor = MB10Colors.borderMuted,
        fillColor = MB10Colors.surfaceRaised,
        cut = 6.dp,
        contentPadding = 0.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 7.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(label, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
            AppToggle(checked, onCheckedChange)
        }
    }
}

