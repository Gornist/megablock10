package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.app.ui.screens.CallLogRow
import com.megablok10.app.ui.screens.CallOverlay
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIcons
import org.junit.Rule
import org.junit.Test

/** M4.2 плана миграции: экран «Звонки» и оверлей (входящий/идущий) — фейковые данные. */
class CallsScreenTest {
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

    private fun entry(peer: String, direction: String, outcome: String, started: Long, ended: Long) =
        CallLogEntity(peerPubKeyB64 = peer, peerCallsign = peer, direction = direction, outcome = outcome, startedAt = started, endedAt = ended)

    @Test
    fun log() = snap("calls_log") {
        CallLogRow(entry("Вобла", CallDirection.INCOMING, CallOutcome.COMPLETED, 1_700_000_000_000L, 1_700_000_102_000L), onClick = {})
        CallLogRow(entry("Киса", CallDirection.INCOMING, CallOutcome.MISSED, 1_700_000_010_000L, 1_700_000_010_000L), onClick = {})
        CallLogRow(entry("Лом", CallDirection.OUTGOING, CallOutcome.COMPLETED, 1_700_000_020_000L, 1_700_000_057_000L), onClick = {})
    }

    @Test
    fun emptyState() = snap("calls_empty") {
        MbEmptyState(MbIcons.Phone, "Звонков пока не было", "Отсканируйте QR-код другого игрока в Профиле, чтобы иметь возможность позвонить.")
    }

    @Test
    fun ringingIncoming() = snap("calls_ringing_incoming") {
        CallOverlay(
            state = CallUiState(phase = CallPhase.INCOMING_RINGING, peerCallsign = "Вобла", callId = "1", startedAt = 0L, audioConnected = false),
            peerFaction = "Вольные",
            onAccept = {},
            onEnd = {}
        )
    }

    @Test
    fun activeCallBanner() = snap("calls_active_banner") {
        CallOverlay(
            state = CallUiState(phase = CallPhase.IN_CALL, peerCallsign = "Вобла", callId = "1", startedAt = System.currentTimeMillis() - 102_000L, audioConnected = true),
            peerFaction = "Вольные",
            onAccept = {},
            onEnd = {}
        )
    }
}
