package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.ui.screens.AnnouncementDialog
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsDefault
import org.junit.Rule
import org.junit.Test

/** M4.7 плана миграции: окно объявления мастера — тон Default (не служебный жёлтый), узнаётся по иконке колокола. */
class AnnouncementDialogTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg).padding(10.dp)) { content() }
            }
        }
    }

    @Test
    fun single() = snap("announcement_single") {
        AnnouncementDialog(count = 1, body = "Сбор у входа в 22:00, форма обязательна.", onLater = {}, onAccept = {})
    }

    @Test
    fun multiple() = snap("announcement_multiple") {
        AnnouncementDialog(
            count = 2,
            body = "Сбор у входа в 22:00, форма обязательна.\n\nСБ усилила патрули на 37-м этаже.",
            onLater = {}, onAccept = {}
        )
    }
}
