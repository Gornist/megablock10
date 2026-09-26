package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.megablok10.app.di.settingsViewModel
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDialogTone
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbField
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbTile
import com.megablok10.app.ui.theme.MbTileTone
import com.megablok10.app.ui.theme.MbTypography
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * M4.6 плана миграции: узлы рядом (мешь-сеть), очередь синка и журнал — раньше жили внутри «Настроек» одним длинным
 * списком, теперь отдельная вкладка (гайдлайн, раздел 5: «Профиль / Настройки / Сеть»). Данные и действия те же, что
 * были в SettingsScreen до переноса: settingsViewModel не заводили заново.
 */
@Composable
fun NetworkScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val c = LocalMbColors.current
    val settings = appViewModel { settingsViewModel() }
    val onlinePeers by settings.peers.collectAsStateWithLifecycle()
    val pendingChanges by settings.pendingChanges.collectAsStateWithLifecycle()
    val collectorReachable by settings.collectorReachable.collectAsStateWithLifecycle()
    var collectorUrl by remember { mutableStateOf(settings.collectorUrl()) }
    var gameSecret by remember { mutableStateOf(settings.gameSecret()) }
    var collectorHelp by remember { mutableStateOf(false) }
    var sizeKb by remember { mutableLongStateOf(Mb10Log.sizeBytes() / 1024) }
    var mark by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    var confirmingClear by remember { mutableStateOf(false) }
    val provisioned = remember { settings.isProvisioned() }
    val provisionRejected = remember { settings.isProvisionRejected() }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = MbDimens.blockGap),
        verticalArrangement = Arrangement.spacedBy(MbDimens.blockGap)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MbDimens.rowGap)) {
            MbTile(
                "Мешь-сеть", modifier = Modifier.weight(1f),
                value = "${onlinePeers.size}", valueUnit = "в сети",
                tone = if (onlinePeers.isNotEmpty()) MbTileTone.Ok else MbTileTone.Neutral,
                subItems = listOf("рядом через NSD")
            )
            MbTile(
                "Очередь синка", modifier = Modifier.weight(1f),
                value = "$pendingChanges",
                tone = if (pendingChanges == 0) MbTileTone.Ok else MbTileTone.Neutral,
                subItems = listOf(if (pendingChanges > 0) "ждут коллектора" else "всё отправлено")
            )
        }
        MbTile("Журнал", modifier = Modifier.fillMaxWidth(), value = "$sizeKb", valueUnit = "КБ", subItems = listOf("хранится ~16 МБ, старое вытесняется"))

        MbSectionTitle("Мастерский коллектор", meta = if (collectorReachable) "на связи" else "нет связи")
        Text(
            if (collectorHelp) "Скрыть подсказки" else "Подробнее",
            style = MbTypography.meta, color = c.acc,
            modifier = Modifier.clickable { collectorHelp = !collectorHelp }.padding(vertical = 4.dp)
        )
        if (collectorHelp) {
            Text(
                "Адрес сервера дашборда в игровой сети — сюда уходит история изменений. Пустой адрес отключает отправку, " +
                    "игра работает как обычно. Код игры нужен, если мастер задал его на сервере (GAME_SECRET): без него " +
                    "запросы к коллектору будут отклонены.",
                style = MbTypography.meta, color = c.ink2
            )
        }
        if (provisionRejected) {
            Text(
                "Сервер не принял код персонажа: он использован на другом телефоне или заменён. Обратитесь к мастеру за " +
                    "новым кодом, затем сделайте сброс сессии.",
                style = MbTypography.meta, color = c.bad
            )
        }
        if (provisioned) {
            Text(
                "Сервер и код игры настроены мастером через QR персонажа и здесь не меняются.",
                style = MbTypography.meta, color = c.ink2
            )
        } else {
            MbField(value = collectorUrl, onValueChange = { collectorUrl = it }, placeholder = settings.defaultUrl.ifBlank { "http://адрес-сервера:порт" })
            MbButton("Сохранить адрес коллектора", kind = MbButtonKind.Ghost, onClick = { settings.saveCollectorUrl(collectorUrl) })
            MbField(value = gameSecret, onValueChange = { gameSecret = it }, placeholder = "код игры")
            MbButton("Сохранить код игры", kind = MbButtonKind.Ghost, onClick = { settings.saveGameSecret(gameSecret) })
        }

        MbSectionTitle("Журнал приложения")
        Text(
            "Подробный журнал работы приложения (сеть, сообщения, деньги, синхронизация). Без текстов сообщений и паролей. После проверки отправьте архив.",
            style = MbTypography.meta, color = c.ink2
        )
        MbField(value = mark, onValueChange = { mark = it }, placeholder = "метка: что вы сейчас делаете")
        Row(horizontalArrangement = Arrangement.spacedBy(MbDimens.rowGap)) {
            MbButton(
                "Метка в журнал", kind = MbButtonKind.Ghost, keyIcon = MbIcons.Pen, modifier = Modifier.weight(1f),
                onClick = {
                    if (mark.isNotBlank()) {
                        Mb10Log.event("MARK", "mark", "text" to mark.trim())
                        mark = ""; status = "Метка записана"
                        scope.launch { Mb10Log.flush(); sizeKb = Mb10Log.sizeBytes() / 1024 }
                    }
                }
            )
            MbButton(
                "Отправить журнал", keyIcon = MbIcons.Upload, modifier = Modifier.weight(1f),
                onClick = {
                    scope.launch {
                        Mb10Log.event("Settings", "log_export_requested")
                        val zip = withContext(Dispatchers.IO) { runCatching { Mb10Log.exportZip(context, settings.deviceReport()) }.getOrNull() }
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
        }
        MbButton("Очистить журнал", kind = MbButtonKind.Ghost, onClick = { confirmingClear = true })
        status?.let { Text(it, style = MbTypography.meta, color = c.acc) }
    }

    if (confirmingClear) {
        MbDialog(
            onDismissRequest = { confirmingClear = false },
            icon = MbIcons.Reset,
            title = "Очистить журнал?",
            tone = MbDialogTone.Danger,
            actions = listOf(
                MbDialogAction("Очистить", MbButtonKind.Danger) {
                    confirmingClear = false
                    Mb10Log.clear()
                    Mb10Log.event("Settings", "log_cleared")
                    scope.launch { Mb10Log.flush(); sizeKb = Mb10Log.sizeBytes() / 1024; status = "Журнал очищен" }
                },
                MbDialogAction("Отмена", MbButtonKind.Quiet) { confirmingClear = false }
            )
        ) {
            Text("Делайте это перед новой проверкой. Старые записи пропадут безвозвратно.")
        }
    }
}
