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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.AppDialog
import com.megablok10.app.ui.theme.AppToggle
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.Chip
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OutlineButton
import com.megablok10.app.ui.theme.SectionLabel

@Composable
fun SettingsScreen(onResetIdentity: () -> Unit, onOpenMasterTool: () -> Unit = {}) {
    var pushEnabled by remember { mutableStateOf(true) }
    var soundEnabled by remember { mutableStateOf(false) }
    var confirmingReset by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionLabel("Приложение")
        ToggleRow("Push-уведомления", pushEnabled) { pushEnabled = it }
        Spacer(Modifier.height(10.dp))
        ToggleRow("Звук при новом сообщении", soundEnabled) { soundEnabled = it }

        Spacer(Modifier.height(16.dp))
        SectionLabel("Сеть и данные")
        NetworkRow("Мешь-сеть", "последняя синхронизация 21:40", "онлайн")
        NetworkRow("База шардов", "загружена мастерами перед игрой", "v12")

        Spacer(Modifier.height(16.dp))
        SectionLabel("Персонаж")
        // Смена фракции — решение мастера вручную вне приложения, здесь этому неоткуда взяться.
        // Раньше это была вечно задизейбленная кнопка (нерабочая форма вместо неё вводит в
        // заблуждение — неясно, почему не жмётся); теперь та же информация обычным текстом.
        Text(
            "Смена фракции — по решению мастера, вручную вне приложения",
            color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp
        )
        Spacer(Modifier.height(12.dp))
        OutlineButton("Сбросить сессию персонажа", modifier = Modifier.fillMaxWidth(), accentColor = MB10Colors.danger, onClick = { confirmingReset = true })

        Spacer(Modifier.height(16.dp))
        SectionLabel("Мастеру")
        OutlineButton("Мастерская — генерация QR точек и шардов", modifier = Modifier.fillMaxWidth(), borderColor = MB10Colors.inkFaint, onClick = onOpenMasterTool)
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
    ChamferedPanel(
        borderColor = MB10Colors.inkFaint,
        fillColor = MB10Colors.bg1,
        cut = 6.dp,
        contentPadding = 0.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(label, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
            AppToggle(checked, onCheckedChange)
        }
    }
}

@Composable
private fun NetworkRow(name: String, meta: String, badge: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 9.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(name, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
            Text(meta, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
        }
        Chip(badge, color = MB10Colors.inkMuted)
    }
}
