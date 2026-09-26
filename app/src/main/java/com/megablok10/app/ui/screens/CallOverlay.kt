package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbBanner
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDialogCard
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbPortrait
import com.megablok10.app.ui.theme.MbTypography
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Входящий/исходящий — MbDialogCard на весь экран (звонок требует немедленного внимания, как настоящий рингтон).
 * IN_CALL — MbBanner сверху содержимого (раздел 5 гайдлайна: «разговор» — зелёная плашка): звонок уже принят, игрок
 * продолжает пользоваться остальным приложением, плашка не должна в этом мешать.
 */
@Composable
fun CallOverlay(state: CallUiState, peerFaction: String?, onAccept: () -> Unit, onEnd: () -> Unit) {
    if (state.phase == CallPhase.IDLE) return

    if (state.phase == CallPhase.IN_CALL) {
        ActiveCallBanner(state, onEnd)
    } else {
        RingingCard(state, peerFaction, onAccept, onEnd)
    }
}

@Composable
private fun RingingCard(state: CallUiState, peerFaction: String?, onAccept: () -> Unit, onEnd: () -> Unit) {
    val incoming = state.phase == CallPhase.INCOMING_RINGING
    val c = LocalMbColors.current
    Box(
        modifier = Modifier.fillMaxSize().background(c.bg.copy(alpha = 0.92f)).padding(MbDimens.screenPadding),
        contentAlignment = Alignment.Center
    ) {
        MbDialogCard(
            icon = MbIcons.Phone,
            title = if (incoming) "Входящая трансмиссия" else "Исходящая трансмиссия",
            wideActions = incoming,
            actions = if (incoming) {
                listOf(
                    MbDialogAction("Отклонить", MbButtonKind.Danger, MbIcons.Close, onEnd),
                    MbDialogAction("Принять", MbButtonKind.Success, MbIcons.Phone, onAccept)
                )
            } else {
                listOf(MbDialogAction("Отменить вызов", MbButtonKind.Danger, onClick = onEnd))
            }
        ) {
            Column(Modifier.fillMaxWidth().padding(vertical = MbDimens.blockGap), horizontalAlignment = Alignment.CenterHorizontally) {
                MbPortrait(state.peerCallsign.take(1).uppercase(), size = MbDimens.portraitCall)
                Spacer(Modifier.height(MbDimens.blockGap))
                Text(state.peerCallsign.uppercase(), style = MbTypography.cardTitle, color = c.inkStrong)
                Spacer(Modifier.height(4.dp))
                Text(
                    (peerFaction?.let { "$it · " } ?: "") + (if (incoming) "вызывает вас" else "дозваниваемся…"),
                    style = MbTypography.dialogText,
                    color = c.ink2
                )
            }
        }
    }
}

/** Компактная плашка активного звонка сверху содержимого — портрет, позывной, живой таймер, кнопка завершения. */
@Composable
private fun ActiveCallBanner(state: CallUiState, onEnd: () -> Unit) {
    var elapsedSeconds by remember(state.callId) { mutableLongStateOf(0L) }
    LaunchedEffect(state.callId, state.startedAt) {
        while (true) {
            elapsedSeconds = ((System.currentTimeMillis() - state.startedAt) / 1000).coerceAtLeast(0)
            delay(1000)
        }
    }
    val minutes = elapsedSeconds / 60
    val seconds = elapsedSeconds % 60
    Box(Modifier.fillMaxWidth().padding(horizontal = MbDimens.screenPadding, vertical = MbDimens.rowGap)) {
        MbBanner(
            lead = { MbPortrait(state.peerCallsign.take(1).uppercase(), size = MbDimens.portraitBanner, ink = LocalMbColors.current.ok) },
            title = state.peerCallsign,
            sub = "● " + (if (state.audioConnected) "В ЭФИРЕ" else "СОЕДИНЕНИЕ") + " · %d:%02d".format(minutes, seconds),
            action = { MbButton("Завершить", onClick = onEnd, kind = MbButtonKind.Alert, inline = true) }
        )
    }
}
