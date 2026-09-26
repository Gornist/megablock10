package com.megablok10.app.screenshots

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbCard
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbFormRow
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbListItemState
import com.megablok10.app.ui.theme.MbPortrait
import com.megablok10.app.ui.theme.MbQr
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTile
import com.megablok10.app.ui.theme.MbTileTone
import com.megablok10.app.ui.theme.MbToggle
import com.megablok10.app.ui.theme.MbTypography
import org.junit.Rule
import org.junit.Test

/**
 * M4.6 плана миграции: Профиль/Настройки/Сеть — фейковые данные, без ViewModel/AppGraph (их с Paparazzi не поднять).
 * Строки-обёртки конкретных экранов (ContactRow, RevealableQr и т.п.) остаются private — снимок собирает тот же вид
 * из общих Mb*-компонентов напрямую, как CyberdeckScreenTest делает для DaemonRow/ShardRow.
 */
class ProfileScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg).padding(10.dp)) {
                    Column { content() }
                }
            }
        }
    }

    @Test
    fun profileCards() = snap("profile_cards") {
        val c = LocalMbColors.current
        MbCard(lead = { MbPortrait("Ш", size = 58.dp) }) {
            Text("Шрам", style = MbTypography.cardTitle, color = c.inkStrong)
            Text("Вольные", style = MbTypography.rowSub, color = c.ink2)
            Text("КЛЮЧ 7F3A…C21", style = MbTypography.demonCode, color = c.acc)
        }
        MbCard(lead = { MbQr(bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888), contentDescription = "QR-код контакта", size = 96.dp) }) {
            Text("Мой QR-код.", style = MbTypography.cardTitle, color = c.inkStrong)
            Text("Покажите игроку — он отсканирует и добавит вас в контакты.", style = MbTypography.rowSub, color = c.ink2)
        }
    }

    @Test
    fun contactsList() = snap("profile_contacts") {
        MbListItem(title = "Вобла", sub = "Вольные", trail = listOf({ MbTag("в сети", tone = MbTagTone.Ok) }), plate = true)
        MbListItem(title = "Шептун", sub = "Сварщики", plate = true, state = MbListItemState.Off)
    }

    @Test
    fun contactsEmpty() = snap("profile_contacts_empty") {
        MbEmptyState(MbIcons.User, "Контактов пока нет", "Отсканируйте QR-код другого игрока, чтобы добавить его.")
    }

    @Test
    fun settingsToggles() = snap("profile_settings") {
        val c = LocalMbColors.current
        MbSectionTitle("Уведомления")
        MbFormRow("Push-уведомления") { MbToggle(true, {}) }
        MbFormRow("Звук при новом сообщении") { MbToggle(false, {}) }
        MbFormRow("Отчёты о прочтении") { MbToggle(true, {}) }
        MbSectionTitle("Опасная зона")
        Text("Смена фракции — по решению мастера, вручную вне приложения.", style = MbTypography.meta, color = c.ink2)
        MbButton("Сбросить сессию персонажа", kind = MbButtonKind.Danger, onClick = {})
    }

    @Test
    fun networkTiles() = snap("profile_network") {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            MbTile("Мешь-сеть", value = "3", valueUnit = "в сети", tone = MbTileTone.Ok, subItems = listOf("рядом через NSD"), modifier = Modifier.weight(1f))
            MbTile("Очередь синка", value = "0", tone = MbTileTone.Ok, subItems = listOf("всё отправлено"), modifier = Modifier.weight(1f))
        }
        MbTile("Журнал", value = "820", valueUnit = "КБ", subItems = listOf("хранится ~16 МБ, старое вытесняется"), modifier = Modifier.fillMaxWidth())
    }
}
