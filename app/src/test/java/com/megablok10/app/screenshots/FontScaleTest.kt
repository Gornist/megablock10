package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.breach.BreachResult
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.ResultOverlay
import com.megablok10.app.breach.RewardOutcome
import com.megablok10.app.breach.Tier
import com.megablok10.app.ui.screens.AnnouncementDialog
import com.megablok10.app.ui.screens.ConversationRow
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbAppShell
import com.megablok10.app.ui.theme.MbColorsBreach
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbMetaLine
import com.megablok10.app.ui.theme.MbNavItem
import org.junit.Rule
import org.junit.Test

/**
 * M6 плана миграции UI: масштаб шрифта 1,3× не должен ломать вёрстку (гайдлайн, раздел 3 и чеклист раздела 11).
 * Экраны — самые тесные по месту (нижнее меню с бейджами, хлебные крошки шапки, тесная сетка взлома, окно с
 * двумя кнопками) с заведомо длинным текстом, чтобы перенос/обрезание сработали, если они вообще должны сработать.
 * Ловит переполнение и наезжающие друг на друга элементы по картинке; не заменяет прогон на реальном устройстве
 * с TalkBack и настоящим `fontScale` системы — см. docs/live-test-plan.md, Т13.
 */
class FontScaleTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = 1.3f, softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg).padding(10.dp)) {
                    Column { content() }
                }
            }
        }
    }

    // Длинные позывной/фракция и оба счётчика меню на пределе (99) — самый тесный вариант шапки+меню сразу.
    private val navItems = listOf(
        MbNavItem("chat", MbIcons.Chat, "Чат", badge = 99),
        MbNavItem("calls", MbIcons.Phone, "Звонки", badge = 99),
        MbNavItem("hack", MbIcons.Hack, "Кибердека"),
        MbNavItem("wallet", MbIcons.Wallet, "Финансы")
    )

    @Test
    fun appShell() = paparazzi.snapshot("fontscale_app_shell") {
        CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
            MbAppShell(
                items = navItems, selectedId = "chat", onSelect = {},
                portraitLetter = "Ш", callsign = "Молчаливый Шершень", faction = "фракция · Отряд «Ночная стража»",
                balance = "€$ 1 240 000", onlineNodes = 7
            ) {
                MbMetaLine("содержимое экрана")
            }
        }
    }

    @Test
    fun chatInbox() = snap("fontscale_chat_inbox") {
        ConversationRow(title = "Фракция: Отряд «Ночная стража»", preview = "Шептун: сбор у бойлерной в полночь, форма обязательна для всех", time = 1_700_000_000_000L, onClick = {})
        ConversationRow(title = "Молчаливый Шершень", preview = "Два. Нужен ПРИЗРАК, иначе тебя срисуют через 4 минуты", time = 1_700_000_001_000L, onClick = {})
    }

    private val daemons = listOf(
        Daemon("d1", "Чёрный занавес", listOf("7A", "BD", "55"), tier = Tier.HARD, effect = DaemonEffect.BLACKOUT),
        Daemon("d2", "Шифровальный ключ доступа", listOf("7A", "E9"), tier = Tier.HARD, effect = DaemonEffect.DECRYPT)
    )

    @Test
    fun breachResult() = paparazzi.snapshot("fontscale_breach_result") {
        CompositionLocalProvider(LocalMbColors provides MbColorsBreach) {
            Box(Modifier.background(MbColorsBreach.bg).padding(10.dp)) {
                Box(Modifier.height(500.dp)) {
                    ResultOverlay(
                        result = BreachResult(daemons, setOf("d1")),
                        failMessage = "", rewardOutcome = RewardOutcome(60, listOf("Спецификация энергоблока К-7"), emptyList(), false, setOf(DaemonEffect.BLACKOUT)),
                        secAlertStatus = "отправлен фракции «Арасака»", actionLabel = "Новый контейнер", onAction = {}
                    )
                }
            }
        }
    }

    @Test
    fun announcementDialog() = snap("fontscale_announcement") {
        AnnouncementDialog(
            count = 2,
            body = "Сбор у входа в 22:00, форма обязательна для всех подразделений без исключения.\n\nСБ усилила патрули на 37-м этаже, будьте осторожны.",
            onLater = {}, onAccept = {}
        )
    }
}
