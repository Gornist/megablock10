package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.identity.Identity
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OutlineButton

/**
 * Полноэкранный оверлей звонка поверх любой вкладки — звонок может прийти,
 * пока игрок сидит в шардах или в кошельке, ждать переключения на чат нельзя.
 * IN_CALL — это только "обе стороны договорились созвониться" (сигнализация
 * прошла), реальное audioConnected приходит отдельно от ICE и может занять
 * секунду-две после этого — статус честно показывает оба состояния, а не
 * выдаёт сигнализацию за готовое соединение.
 */
@Composable
fun CallOverlay(state: CallUiState, identity: Identity, onAccept: () -> Unit, onEnd: () -> Unit) {
    if (state.phase == CallPhase.IDLE) return

    Box(
        modifier = Modifier.fillMaxSize().background(MB10Colors.bg0.copy(alpha = 0.92f)),
        contentAlignment = Alignment.Center
    ) {
        ChamferedPanel(
            borderColor = MB10Colors.accentPrimary,
            fillColor = MB10Colors.bg1,
            cut = 12.dp,
            doubleCorner = true,
            contentPadding = 24.dp,
            modifier = Modifier.fillMaxWidth().padding(24.dp)
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text(
                    when (state.phase) {
                        CallPhase.OUTGOING_RINGING -> "Вызов"
                        CallPhase.INCOMING_RINGING -> "Входящий вызов"
                        CallPhase.IN_CALL -> "На связи"
                        CallPhase.IDLE -> ""
                    },
                    color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp
                )
                Spacer(Modifier.height(10.dp))
                HexBullet(MB10Colors.accentPrimary, size = 14.dp)
                Spacer(Modifier.height(10.dp))
                Text(state.peerCallsign, color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                Spacer(Modifier.height(6.dp))
                Text(
                    when (state.phase) {
                        CallPhase.OUTGOING_RINGING -> "Дозваниваемся..."
                        CallPhase.INCOMING_RINGING -> "Вызывает вас"
                        CallPhase.IN_CALL -> if (state.audioConnected) "Аудио подключено" else "Соединяем аудио..."
                        CallPhase.IDLE -> ""
                    },
                    color = if (state.phase == CallPhase.IN_CALL && state.audioConnected) MB10Colors.accentPrimary else MB10Colors.inkFaint,
                    fontFamily = JetBrainsMono, fontSize = 10.sp
                )
                Spacer(Modifier.height(22.dp))
                when (state.phase) {
                    CallPhase.INCOMING_RINGING -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlineButton("Принять", accentColor = MB10Colors.accentPrimary, onClick = onAccept)
                        OutlineButton("Отклонить", accentColor = MB10Colors.danger, onClick = onEnd)
                    }
                    CallPhase.OUTGOING_RINGING -> OutlineButton("Отменить вызов", accentColor = MB10Colors.danger, modifier = Modifier.fillMaxWidth(), onClick = onEnd)
                    CallPhase.IN_CALL -> OutlineButton("Завершить", accentColor = MB10Colors.danger, modifier = Modifier.fillMaxWidth(), onClick = onEnd)
                    CallPhase.IDLE -> {}
                }
            }
        }
    }
}
