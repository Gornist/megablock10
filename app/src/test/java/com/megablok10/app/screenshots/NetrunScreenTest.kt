package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.Tier
import com.megablok10.app.netrun.NetrunEntryState
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.screens.NetrunDeckPicker
import com.megablok10.app.ui.screens.NetrunStatus
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsDefault
import org.junit.Rule
import org.junit.Test

/** M3 «Сети»: выбор деки и защищённого слота после скана QR стойки; ход входа (отправка, ожидание, подключено, отказ). */
class NetrunScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private val rack = Mb10Qr.Rack("t03", "10.10.0.10", 7411, "MFkwEwYH", "Подвал, стойка 3")
    private val daemons = listOf(
        Daemon("d1", "Призрак", listOf("1C", "BD", "55"), tier = Tier.HARD, effect = DaemonEffect.BLACKOUT),
        Daemon("d2", "Шахтёр", listOf("7A", "E9"), tier = Tier.HARD, effect = DaemonEffect.MINER),
        Daemon("d3", "Дешифратор", listOf("E9", "FF", "10", "2B"), tier = Tier.HARD, effect = DaemonEffect.DECRYPT),
    )

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg)) { content() }
            }
        }
    }

    @Test
    fun deckPicker() = snap("netrun_deck_picker") {
        NetrunDeckPicker(rack, daemons, ramCapacity = 6, chosen = setOf("d1", "d2"), protectedId = "d1", onToggle = {}, onProtect = {}, onEnter = {}, onCancel = {})
    }

    @Test
    fun deckPickerNothingChosen() = snap("netrun_deck_picker_empty_choice") {
        NetrunDeckPicker(rack, daemons, ramCapacity = 6, chosen = emptySet(), protectedId = null, onToggle = {}, onProtect = {}, onEnter = {}, onCancel = {})
    }

    @Test
    fun statusSending() = snap("netrun_status_sending") { NetrunStatus(NetrunEntryState.Sending(rack), {}, {}) }

    @Test
    fun statusWaitingTimedOut() = snap("netrun_status_waiting_timeout") { NetrunStatus(NetrunEntryState.Waiting(rack, timedOut = true), {}, {}) }

    @Test
    fun statusConnected() = snap("netrun_status_connected") { NetrunStatus(NetrunEntryState.Connected(rack, "s_9f2c41d07a3e5b60"), {}, {}) }

    @Test
    fun statusFailed() = snap("netrun_status_failed") { NetrunStatus(NetrunEntryState.Failed("Вход отклонён: терминал занят. Деки вернутся на телефон."), {}, {}) }
}
