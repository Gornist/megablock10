package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.ui.screens.NetworkContent
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsDefault
import org.junit.Rule
import org.junit.Test

/** Вкладка «Сеть» целиком: NetworkContent — без ViewModel, фейковые данные (сам NetworkScreen с Paparazzi не поднять). */
class NetworkScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, provisioned: Boolean, status: String?) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.fillMaxSize().background(MbColorsDefault.bg).padding(horizontal = 10.dp)) {
                    content(provisioned, status)
                }
            }
        }
    }

    @Composable
    private fun content(provisioned: Boolean, status: String?) = NetworkContent(
        onlineCount = 3, pendingChanges = 0, collectorReachable = true, logSizeKb = 820, status = status,
        provisioned = provisioned, provisionRejected = false, initialUrl = "http://10.10.0.10:8080", initialSecret = "",
        defaultUrl = "", onSaveUrl = {}, onSaveSecret = {}, onMark = { false }, onClearLog = {}, onExportLog = {}
    )

    @Test
    fun manualCollector() = snap("network_manual", provisioned = false, status = null)

    @Test
    fun provisionedByMaster() = snap("network_provisioned", provisioned = true, status = "Метка записана")
}
