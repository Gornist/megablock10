package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.megablok10.app.identity.Identity
import com.megablok10.app.ui.theme.MbBreadcrumb
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbTabItem
import com.megablok10.app.ui.theme.MbTabs
import com.megablok10.kit.mesh.OnlinePlayer

private const val SEGMENT_PROFILE = 0
private const val SEGMENT_SETTINGS = 1
private const val SEGMENT_NETWORK = 2

/**
 * Профиль / Настройки / Сеть — три вкладки одного экрана за аватаром в шапке, а не отдельные табы внизу (их и так
 * четыре — чат/звонки/кибердека/финансы). Три сегмента вместо прежних двух (M4.6 плана миграции): «Сеть» была частью
 * «Настроек» одним длинным списком, гайдлайн (раздел 5) держит их отдельно. Экран остаётся отдельным полноэкранным
 * флоу поверх оболочки (`MbAppShell`), как решили в M3, — сама оболочка вкладку профиля не заводит.
 */
@Composable
fun ProfileScreen(
    identity: Identity,
    onMessageContact: (String) -> Unit,
    onCallContact: (OnlinePlayer) -> Unit,
    onResetIdentity: () -> Unit,
    onBack: () -> Unit
) {
    var segment by remember { mutableIntStateOf(SEGMENT_PROFILE) }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbBreadcrumb(parts = listOf("Профиль"), icon = MbIcons.User) {
            MbIconButton(MbIcons.Close, "Назад", onBack)
        }
        MbTabs(
            items = listOf(MbTabItem(label = "Профиль"), MbTabItem(label = "Настройки"), MbTabItem(label = "Сеть")),
            selected = segment,
            onSelect = { segment = it }
        )
        Box(Modifier.weight(1f)) {
            when (segment) {
                SEGMENT_PROFILE -> StatusScreen(identity, onMessageContact = onMessageContact, onCallContact = onCallContact)
                SEGMENT_SETTINGS -> SettingsScreen(onResetIdentity = onResetIdentity)
                SEGMENT_NETWORK -> NetworkScreen()
            }
        }
    }
}
