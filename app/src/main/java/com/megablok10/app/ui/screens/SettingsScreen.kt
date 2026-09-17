package com.megablok10.app.ui.screens

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
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppDialog
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
fun SettingsScreen(onResetIdentity: () -> Unit, onOpenMasterTool: () -> Unit = {}) {
    var pushEnabled by remember { mutableStateOf(true) }
    var soundEnabled by remember { mutableStateOf(false) }
    var confirmingReset by remember { mutableStateOf(false) }
    val onlinePeers by PresenceService.peers.collectAsState()

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionLabel("Приложение")
        ToggleRow("Push-уведомления", pushEnabled) { pushEnabled = it }
        Spacer(Modifier.height(10.dp))
        ToggleRow("Звук при новом сообщении", soundEnabled) { soundEnabled = it }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Сеть и данные")
        ListRow(trailing = { StatusChip("${onlinePeers.size} в сети", tone = ChipTone.Neutral) }) {
            Text("Мешь-сеть", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
            Text("устройства рядом обнаруживаются через NSD", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
        }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Персонаж")
        // Смена фракции — решение мастера вручную вне приложения, здесь этому неоткуда взяться.
        // Раньше это была вечно задизейбленная кнопка (нерабочая форма вместо неё вводит в
        // заблуждение — неясно, почему не жмётся); теперь та же информация обычным текстом.
        Text(
            "Смена фракции — по решению мастера, вручную вне приложения",
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp
        )
        Spacer(Modifier.height(12.dp))
        AppButton("Сбросить сессию персонажа", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Danger, onClick = { confirmingReset = true })

        Spacer(Modifier.height(16.dp))
        SectionLabel("Мастеру")
        AppButton("Мастерская — генерация QR контейнеров, шардов и RAM", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, onClick = onOpenMasterTool)
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
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(label, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
            AppToggle(checked, onCheckedChange)
        }
    }
}

