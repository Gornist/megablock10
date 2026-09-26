package com.megablok10.app.screenshots

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbActionBar
import com.megablok10.app.ui.theme.MbActionBarItem
import com.megablok10.app.ui.theme.MbBanner
import com.megablok10.app.ui.theme.MbBannerTone
import com.megablok10.app.ui.theme.MbBubble
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbBuffer
import com.megablok10.app.ui.theme.MbCard
import com.megablok10.app.ui.theme.MbCodeMatrix
import com.megablok10.app.ui.theme.MbColorScheme
import com.megablok10.app.ui.theme.MbColorsBreach
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbComposer
import com.megablok10.app.ui.theme.MbDaySep
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDialogCard
import com.megablok10.app.ui.theme.MbDialogTone
import com.megablok10.app.ui.theme.MbDone
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbFormRow
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbKeyCap
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbListItemState
import com.megablok10.app.ui.theme.MbLog
import com.megablok10.app.ui.theme.MbMatrixCell
import com.megablok10.app.ui.theme.MbMatrixCellKind
import com.megablok10.app.ui.theme.MbMetaLine
import com.megablok10.app.ui.theme.MbPanel
import com.megablok10.app.ui.theme.MbPayBubble
import com.megablok10.app.ui.theme.MbPortrait
import com.megablok10.app.ui.theme.MbProgress
import com.megablok10.app.ui.theme.MbQr
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbSkeleton
import com.megablok10.app.ui.theme.MbSlider
import com.megablok10.app.ui.theme.MbStatusText
import com.megablok10.app.ui.theme.MbStatusTone
import com.megablok10.app.ui.theme.MbStrip
import com.megablok10.app.ui.theme.MbTabItem
import com.megablok10.app.ui.theme.MbTabs
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTile
import com.megablok10.app.ui.theme.MbTileTone
import com.megablok10.app.ui.theme.MbTimer
import com.megablok10.app.ui.theme.MbToggle
import org.junit.Rule
import org.junit.Test

/**
 * Каталог новой дизайн-системы (аналог вкладки «Компоненты» прототипа docs/ux/prototype/mb10-ui-kit.html) — по нему
 * проверяется, что перенос в Compose совпадает с эталоном «на глаз» (M2 плана миграции). Экраны из этих компонентов
 * ещё не собраны (M4) — старые компоненты и ScreenshotTest продолжают жить рядом до M5.
 */
class KitCatalogTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, colors: MbColorScheme = MbColorsDefault, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides colors) {
                Box(Modifier.background(colors.bg).padding(10.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
                }
            }
        }
    }

    @Test
    fun atoms() = snap("kit_atoms") {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MbButton("Обычная", {}, Modifier.weight(1f))
            MbButton("Выключена", {}, Modifier.weight(1f), enabled = false)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MbButton("Ghost", {}, Modifier.weight(1f), kind = MbButtonKind.Ghost)
            MbButton("Success", {}, Modifier.weight(1f), kind = MbButtonKind.Success)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MbButton("Отклонить", {}, Modifier.weight(1f), kind = MbButtonKind.Danger, keyIcon = MbIcons.Close)
            MbButton("Принять", {}, Modifier.weight(1f), kind = MbButtonKind.Success, keyIcon = MbIcons.Phone)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MbButton("Завершить", {}, kind = MbButtonKind.Alert, inline = true)
            MbButton("Закрыть", {}, kind = MbButtonKind.Quiet, inline = true)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MbIconButton(MbIcons.Phone, "Позвонить", {})
            MbIconButton(MbIcons.Send, "Перевод", {})
            MbKeyCap(MbIcons.Close)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MbTag("новый", filled = true)
            MbTag("нужен дешифратор", tone = MbTagTone.Warn)
            MbTag("установлен", tone = MbTagTone.Ok)
            MbTag("не вошёл", tone = MbTagTone.Bad)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MbStatusText("подтверждено", MbStatusTone.Ok)
            MbStatusText("ждёт принятия", MbStatusTone.Warn)
            MbStatusText("не доставлено", MbStatusTone.Bad)
        }
        MbActionBar(listOf(MbActionBarItem(MbIcons.Phone, "Позвонить") {}, MbActionBarItem(MbIcons.Close, "Закрыть") {}))
    }

    @Test
    fun structure() = snap("kit_structure") {
        MbTabs(listOf(MbTabItem(MbIcons.Mail, "Сообщения"), MbTabItem(MbIcons.Phone, "Звонки")), selected = 0, onSelect = {})
        MbBreadcrumbSample()
        MbSectionTitle("Контакты", meta = "4")
        MbListItem(
            title = "Вобла", sub = "нажата",
            lead = { androidx.compose.material3.Icon(androidx.compose.ui.res.painterResource(MbIcons.User), null) },
            trail = listOf({ MbTag("2", filled = true) }),
            forcePressedPreview = true
        )
        MbListItem(
            title = "Киса", sub = "обычная",
            lead = { androidx.compose.material3.Icon(androidx.compose.ui.res.painterResource(MbIcons.User), null) },
            trail = listOf({ MbTag("1", filled = true) })
        )
        MbListItem(title = "Лом", sub = "прочитанная", state = MbListItemState.Muted)
        MbListItem(title = "Шептун", sub = "не в сети", state = MbListItemState.Off)
        MbListItem(title = "Журнал охраны 37-Б", plate = true, mark = true, forcePressedPreview = true)
        MbListItem(title = "Письмо Шептуну", plate = true, mark = true, trail = listOf({ MbTag("новый", filled = true) }))
    }

    @Composable
    private fun MbBreadcrumbSample() {
        com.megablok10.app.ui.theme.MbBreadcrumb(listOf("Сообщения", "Вобла"), icon = MbIcons.Mail) {
            MbIconButton(MbIcons.Phone, "Позвонить", {})
        }
        MbMetaLine("● в сети · Вольные · ключ 9C1E…04B", tone = com.megablok10.app.ui.theme.MbMetaTone.Ok)
    }

    @Test
    fun surfaces() = snap("kit_surfaces") {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            MbTile("Баланс", Modifier.weight(1f), value = "1 240", valueUnit = "€$", tone = MbTileTone.Money, big = true, subItems = listOf("+335 за сутки", "−170 отправлено"))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            MbTile("Коллектор", Modifier.weight(1f), value = "На связи", leadingDot = true, tone = MbTileTone.Ok)
            MbTile("Мешь-сеть", Modifier.weight(1f), value = "7 узлов")
        }
        MbCard(lead = { MbPortrait("Ш", size = 58.dp) }) {
            androidx.compose.material3.Text("Шрам", color = LocalMbColors.current.inkStrong)
            androidx.compose.material3.Text("Вольные · жилец 37-Б", color = LocalMbColors.current.label)
        }
        MbQr(bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888), contentDescription = "QR-код профиля")
    }

    @Test
    fun dialogsFormsStates() = snap("kit_dialogs_forms_states") {
        MbDialogCard(
            icon = MbIcons.Bell,
            title = "Объявление мастера",
            actions = listOf(MbDialogAction("Закрыть", MbButtonKind.Quiet) {})
        ) {
            androidx.compose.material3.Text("В 00:30 СБ блока проводит проверку пропусков.")
        }
        MbDialogCard(
            icon = MbIcons.Wallet,
            title = "Подтверждение перевода",
            tone = MbDialogTone.Danger,
            wideActions = true,
            actions = listOf(
                MbDialogAction("Отмена", MbButtonKind.Danger) {},
                MbDialogAction("Подтвердить", MbButtonKind.Success) {}
            )
        ) {
            androidx.compose.material3.Text("Перевести 120 €$ игроку ЛОМ?")
        }
        MbBanner(lead = { MbPortrait("В", size = 30.dp) }, title = "Вобла", sub = "● В ЭФИРЕ · 01:42", action = { MbButton("Завершить", {}, kind = MbButtonKind.Alert, inline = true) })
        MbBanner(
            lead = { androidx.compose.material3.Icon(androidx.compose.ui.res.painterResource(MbIcons.NoSignal), null, tint = LocalMbColors.current.bad) },
            title = "Нет связи", sub = "коллектор 10.10.0.10 · 3 записи ждут", tone = MbBannerTone.Danger,
            action = { MbButton("Повторить", {}, kind = MbButtonKind.Danger, inline = true) }
        )
        MbFormRow("Вибрация при сообщении") { MbToggle(true, {}) }
        MbFormRow("Текст в уведомлении") { MbToggle(false, {}) }
        MbFormRow("Яркость подсветки") { MbSlider(70, "70") }
        MbEmptyState(MbIcons.User, "Контактов пока нет", "Отсканируйте QR-код другого игрока, чтобы добавить его.") {
            MbButton("Сканер", {}, kind = MbButtonKind.Primary, keyIcon = MbIcons.Scan, inline = true)
        }
        MbSkeleton(2)
    }

    @Test
    fun bubblesAndComposer() = snap("kit_bubbles_composer") {
        MbDaySep("Сегодня")
        MbBubble(fromMe = false, text = "Два. Нужен ПРИЗРАК.", meta = "23:33")
        MbBubble(fromMe = true, text = "Понял", meta = "23:34 ✓✓")
        MbPayBubble(head = "Перевод · Вобле", value = "50 €$") { androidx.compose.material3.Text("«за наводку»", color = LocalMbColors.current.ink2) }
        MbComposer(value = "", onValueChange = {}, onSend = {})
    }

    @Test
    fun breach() = snap("kit_breach", colors = MbColorsBreach) {
        MbStrip("СЕТЬ ═ ДЕКА", "ПРОТОКОЛ 2.07")
        MbTimer("Время взлома", "34.50") { MbIconButton(MbIcons.Close, "Выйти из взлома", {}) }
        MbProgress(58)
        MbPanel("Буфер", meta = "2 / 6") { MbBuffer(listOf("1C", "BD"), 6) }
        MbPanel("Матрица кодов", meta = "5×5") {
            val row = listOf("E9", "7A", "1C", "55", "BD")
            MbCodeMatrix(
                cells = listOf(
                    row.mapIndexed { i, v -> MbMatrixCell(v, if (i == 2) MbMatrixCellKind.Used else MbMatrixCellKind.Normal) },
                    row.mapIndexed { i, v -> MbMatrixCell(v, if (i == 1) MbMatrixCellKind.Aim else MbMatrixCellKind.Band) }
                )
            )
        }
        MbDone("Демоны загружены · 2 из 3")
        MbLog(listOf("//КОРЕНЬ", "//ЗАГРУЗКА_ЗАВЕРШЕНА"))
    }

    private val navItems = listOf(
        com.megablok10.app.ui.theme.MbNavItem("chat", MbIcons.Chat, "Чат", badge = 3),
        com.megablok10.app.ui.theme.MbNavItem("calls", MbIcons.Phone, "Звонки", badge = 1),
        com.megablok10.app.ui.theme.MbNavItem("hack", MbIcons.Hack, "Кибердека"),
        com.megablok10.app.ui.theme.MbNavItem("wallet", MbIcons.Wallet, "Финансы")
    )

    @Test
    fun appShellWithHeader() = paparazzi.snapshot("kit_app_shell_header") {
        CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
            com.megablok10.app.ui.theme.MbAppShell(
                items = navItems, selectedId = "chat", onSelect = {},
                portraitLetter = "Ш", callsign = "Шрам", faction = "фракция · Вольные", balance = "€$ 1 240", onlineNodes = 7
            ) {
                MbMetaLine("содержимое экрана")
            }
        }
    }

    @Test
    fun appShellNoHeader() = paparazzi.snapshot("kit_app_shell_no_header") {
        CompositionLocalProvider(LocalMbColors provides MbColorsBreach) {
            com.megablok10.app.ui.theme.MbAppShell(
                items = navItems, selectedId = "hack", onSelect = {}, header = false
            ) {
                MbStrip("СЕТЬ ═ ДЕКА", "ПРОТОКОЛ 2.07")
            }
        }
    }
}
