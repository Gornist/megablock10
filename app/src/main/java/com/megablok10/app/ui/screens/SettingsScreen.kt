package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.MB10Toggle
import com.megablok10.app.ui.theme.chamferShape

@Composable
fun SettingsScreen(onResetIdentity: () -> Unit) {
    var pushEnabled by remember { mutableStateOf(true) }
    var soundEnabled by remember { mutableStateOf(false) }
    var confirmingReset by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SettingsSectionLabel("Приложение")
        ToggleRow("Push-уведомления", pushEnabled) { pushEnabled = it }
        Spacer(Modifier.height(10.dp))
        ToggleRow("Звук при новом сообщении", soundEnabled) { soundEnabled = it }

        Spacer(Modifier.height(16.dp))
        SettingsSectionLabel("Сеть и данные")
        NetworkRow("Мешь-сеть", "последняя синхронизация 21:40", "онлайн")
        NetworkRow("База шардов", "загружена мастерами перед игрой", "v12")

        Spacer(Modifier.height(16.dp))
        SettingsSectionLabel("Персонаж")
        ActionButton("Сменить фракцию (по решению мастера)", onClick = {})
        Spacer(Modifier.height(8.dp))
        ActionButton("Сбросить сессию персонажа", danger = true, onClick = { confirmingReset = true })
    }

    if (confirmingReset) {
        AlertDialog(
            onDismissRequest = { confirmingReset = false },
            title = { Text("Сбросить сессию персонажа?") },
            text = { Text("Ключевая пара, позывной и фракция этого устройства будут удалены безвозвратно. Отменить нельзя.") },
            confirmButton = {
                TextButton(onClick = { confirmingReset = false; onResetIdentity() }) {
                    Text("Сбросить", color = MB10Colors.red)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingReset = false }) { Text("Отмена") }
            }
        )
    }
}

@Composable
private fun SettingsSectionLabel(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
        HexBullet(MB10Colors.inkMuted, size = 8.dp)
        Spacer(Modifier.width(6.dp))
        Text(text, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
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
            MB10Toggle(checked, onCheckedChange)
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
        Box(
            modifier = Modifier
                .background(MB10Colors.bg1, chamferShape(4.dp))
                .border(1.dp, MB10Colors.inkFaint, chamferShape(4.dp))
                .padding(horizontal = 7.dp, vertical = 2.dp)
        ) {
            Text(badge, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 9.5.sp)
        }
    }
}

@Composable
private fun ActionButton(label: String, danger: Boolean = false, onClick: () -> Unit) {
    val color = if (danger) MB10Colors.red else MB10Colors.ink0
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, if (danger) MB10Colors.red else MB10Colors.inkFaint, chamferShape(5.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp)
    ) {
        Text(label, color = color, fontFamily = JetBrainsMono, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}
