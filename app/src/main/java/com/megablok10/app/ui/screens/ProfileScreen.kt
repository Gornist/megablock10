package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors

/**
 * Профиль и Настройки — одно место за аватаром в шапке, а не два отдельных
 * таба внизу (как чат/звонки/кибердека/шарды раньше — экранов было слишком
 * много для нижнего бара). Сегменты, тот же паттерн, что уже есть в Чате и
 * Кибердеке, а не слитная страница: StatusScreen и SettingsScreen оба сами
 * по себе прокручиваемые списки, а вложенный скролл внутри скролла в Compose
 * ломается — сегменты показывают только один из них за раз, без этой проблемы.
 */
@Composable
fun ProfileScreen(
    identity: Identity,
    onMessageContact: (String) -> Unit,
    onCallContact: (PeerInfo) -> Unit,
    onResetIdentity: () -> Unit,
    onOpenMasterTool: () -> Unit,
    onBack: () -> Unit
) {
    var segment by remember { mutableStateOf(0) } // 0 = Профиль, 1 = Настройки

    Column(Modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onBack).padding(horizontal = 16.dp, vertical = 10.dp)
        ) {
            Text("←", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text("Профиль", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 13.sp)
        }

        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            listOf("Профиль", "Настройки").forEachIndexed { i, label ->
                val active = i == segment
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .background(if (active) MB10Colors.surfaceSunken else MB10Colors.surfaceRaised)
                        .clickable { segment = i }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(label, color = if (active) MB10Colors.inkPrimary else MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 12.sp)
                }
            }
        }
        Spacer(Modifier.height(4.dp))

        Box(Modifier.weight(1f)) {
            if (segment == 0) {
                StatusScreen(identity, onMessageContact = onMessageContact, onCallContact = onCallContact)
            } else {
                SettingsScreen(onResetIdentity = onResetIdentity, onOpenMasterTool = onOpenMasterTool)
            }
        }
    }
}
