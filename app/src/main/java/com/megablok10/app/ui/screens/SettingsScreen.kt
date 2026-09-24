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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import com.megablok10.app.log.DeviceDiagnostics
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.ui.LocalAppGraph
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
import com.megablok10.app.ui.theme.HamburgerToggle
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.ui.theme.StaggeredReveal
import com.megablok10.app.ui.theme.StatusChip

@Composable
fun SettingsScreen(onResetIdentity: () -> Unit) {
    val context = LocalContext.current
    var pushEnabled by remember { mutableStateOf(true) }
    var soundEnabled by remember { mutableStateOf(false) }
    var confirmingReset by remember { mutableStateOf(false) }
    val graph = LocalAppGraph.current
    val settings = graph.collectorSettings
    val onlinePeers by graph.presence.peers.collectAsState()
    var collectorUrl by remember { mutableStateOf(settings.baseUrl() ?: "") }
    val announcements by graph.announcements.items.collectAsState()
    var gameSecret by remember { mutableStateOf(settings.gameSecret() ?: "") }
    val pendingChanges by remember { graph.db.pendingChangeRecordDao().observeCount() }.collectAsState(initial = 0)

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
        LogSection()

        Spacer(Modifier.height(16.dp))
        if (announcements.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            SectionLabel("Сообщения мастера")
            val format = remember { java.text.SimpleDateFormat("dd.MM HH:mm", java.util.Locale.getDefault()) }
            announcements.take(10).forEachIndexed { index, a ->
                StaggeredReveal(index) {
                    Column {
                        ListRow {
                            Text(a.text, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                            Text(format.format(java.util.Date(a.receivedAt)), color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
                        }
                        Spacer(Modifier.height(6.dp))
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Мастерский коллектор")
        var collectorHelp by remember { mutableStateOf(false) }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { collectorHelp = !collectorHelp }.padding(vertical = 4.dp)) {
            HamburgerToggle(open = collectorHelp, onToggle = { collectorHelp = it })
            Spacer(Modifier.width(8.dp))
            Text(
                if (collectorHelp) "Скрыть подсказки" else "Подробнее",
                color = MB10Colors.accentAction, fontFamily = JetBrainsMono, fontSize = 11.sp
            )
        }
        if (collectorHelp) {
            Text(
                "Адрес сервера дашборда в игровой сети — сюда уходит история изменений. Пустой адрес отключает отправку, игра работает как обычно. " +
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
        val provisioned = remember { settings.isProvisioned() }
        if (remember { settings.isProvisionRejected() }) {
            Text(
                "Сервер не принял код персонажа: он использован на другом телефоне или заменён. Обратитесь к мастеру за новым кодом, затем сделайте сброс сессии.",
                color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 11.sp
            )
            Spacer(Modifier.height(6.dp))
        }
        if (provisioned) {
            // Сервер и код игры пришли по QR персонажа от мастера: правятся только новым QR после сброса сессии.
            Text(
                "Сервер и код игры настроены мастером через QR персонажа и здесь не меняются.",
                color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp
            )
        } else {
        Spacer(Modifier.height(8.dp))
        AppTextField(
            value = collectorUrl,
            onValueChange = { collectorUrl = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = settings.defaultUrl.ifBlank { "http://адрес-сервера:порт" }
        )
        Spacer(Modifier.height(8.dp))
        AppButton(
            "Сохранить адрес коллектора",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Secondary,
            onClick = { settings.setBaseUrl(collectorUrl); Mb10Log.event("Settings", "collector_url_saved", "url" to collectorUrl); graph.collectorSync.wake() }
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
            onClick = { settings.setGameSecret(gameSecret.ifBlank { null }); Mb10Log.event("Settings", "game_secret_saved", "empty" to gameSecret.isBlank()); graph.collectorSync.wake() }
        )
        }

        // Необратимое действие — отдельным блоком внизу, чтобы не нажать по соседству с обычными кнопками.
        Spacer(Modifier.height(28.dp))
        SectionLabel("Опасная зона", color = MB10Colors.accentDanger)
        Text(
            "Смена фракции — по решению мастера, вручную вне приложения.",
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp
        )
        Spacer(Modifier.height(8.dp))
        AppButton("Сбросить сессию персонажа", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Danger, dense = true, onClick = { confirmingReset = true; Mb10Log.event("Settings", "reset_dialog_opened") })
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


/** Журнал приложения: отправить архив на разбор, оставить метку («вышел из зоны точки 2»), очистить перед новой проверкой. */
@Composable
private fun LogSection() {
    val context = LocalContext.current
    val graph = LocalAppGraph.current
    val scope = rememberCoroutineScope()
    var sizeKb by remember { mutableStateOf(Mb10Log.sizeBytes() / 1024) }
    var mark by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    var confirmingClear by remember { mutableStateOf(false) }

    SectionLabel("Журнал")
    Text(
        "Подробный журнал работы приложения (сеть, сообщения, деньги, синхронизация). Без текстов сообщений и паролей. После проверки отправьте архив.",
        color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp
    )
    Spacer(Modifier.height(6.dp))
    ListRow(trailing = { StatusChip("$sizeKb КБ", tone = ChipTone.Neutral) }) {
        Text("Размер журнала", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
        Text("хранится ~16 МБ, старое вытесняется", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
    }
    Spacer(Modifier.height(8.dp))
    AppTextField(value = mark, onValueChange = { mark = it }, modifier = Modifier.fillMaxWidth(), placeholder = "метка: что вы сейчас делаете")
    Spacer(Modifier.height(6.dp))
    AppButton(
        "Записать метку в журнал", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, dense = true,
        onClick = {
            if (mark.isNotBlank()) {
                Mb10Log.event("MARK", "mark", "text" to mark.trim())
                mark = ""; status = "Метка записана"
                scope.launch { Mb10Log.flush(); sizeKb = Mb10Log.sizeBytes() / 1024 }
            }
        }
    )
    Spacer(Modifier.height(6.dp))
    AppButton(
        "Отправить журнал", modifier = Modifier.fillMaxWidth(), dense = true,
        onClick = {
            scope.launch {
                Mb10Log.event("Settings", "log_export_requested")
                val zip = withContext(Dispatchers.IO) {
                    runCatching { Mb10Log.exportZip(context, DeviceDiagnostics.deviceReport(context, graph)) }.getOrNull()
                }
                if (zip == null) { status = "Не удалось собрать архив"; return@launch }
                val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.logs", zip)
                val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                    type = "application/zip"
                    putExtra(android.content.Intent.EXTRA_STREAM, uri)
                    addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startActivity(android.content.Intent.createChooser(send, "Отправить журнал").addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                status = "Архив: ${zip.length() / 1024} КБ"
            }
        }
    )
    Spacer(Modifier.height(6.dp))
    AppButton("Очистить журнал", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, dense = true, onClick = { confirmingClear = true })
    status?.let {
        Spacer(Modifier.height(6.dp))
        Text(it, color = MB10Colors.accentAction, fontFamily = JetBrainsMono, fontSize = 11.sp)
    }
    if (confirmingClear) {
        AppDialog(
            onDismissRequest = { confirmingClear = false },
            title = "Очистить журнал?",
            body = "Делайте это перед новой проверкой. Старые записи пропадут безвозвратно.",
            confirmText = "Очистить",
            onConfirm = {
                confirmingClear = false
                Mb10Log.clear()
                Mb10Log.event("Settings", "log_cleared")
                scope.launch { Mb10Log.flush(); sizeKb = Mb10Log.sizeBytes() / 1024; status = "Журнал очищен" }
            }
        )
    }
}
