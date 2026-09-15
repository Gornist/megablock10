package com.megablok10.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.Chip
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OutlineButton
import com.megablok10.app.ui.theme.chamferShape
import kotlinx.coroutines.delay

/**
 * Входящий/исходящий — полноэкранная карточка (звонок требует немедленного
 * внимания, как настоящий рингтон). IN_CALL — наоборот, компактная плавающая
 * плашка сверху экрана, а не оверлей на весь экран: звонок уже принят, дальше
 * игрок продолжает пользоваться остальным приложением (чат, кибердека и
 * т.д.), плашка не должна в этом мешать — источник паттерна: холо-собеседник
 * в углу кадра в игре, а не модальный диалог.
 */
@Composable
fun CallOverlay(state: CallUiState, identity: Identity, onAccept: () -> Unit, onEnd: () -> Unit) {
    if (state.phase == CallPhase.IDLE) return

    val context = LocalContext.current
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val peerFaction = contacts.find { it.publicKeyB64 == state.peerPubKeyB64 }?.faction

    if (state.phase == CallPhase.IN_CALL) {
        ActiveCallBar(state, onEnd)
    } else {
        RingingCard(state, peerFaction, onAccept, onEnd)
    }
}

@Composable
private fun RingingCard(state: CallUiState, peerFaction: String?, onAccept: () -> Unit, onEnd: () -> Unit) {
    val incoming = state.phase == CallPhase.INCOMING_RINGING

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
                Row(verticalAlignment = Alignment.CenterVertically) {
                    HexBullet(MB10Colors.accentPrimary, size = 6.dp)
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (incoming) "ВХОДЯЩАЯ ТРАНСМИССИЯ" else "ИСХОДЯЩАЯ ТРАНСМИССИЯ",
                        color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp
                    )
                }
                Spacer(Modifier.height(18.dp))
                HoloPortrait(letter = state.peerCallsign.take(1).uppercase(), portraitSize = 150.dp)
                Spacer(Modifier.height(16.dp))
                Text(state.peerCallsign, color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                if (peerFaction != null) {
                    Spacer(Modifier.height(6.dp))
                    Chip(peerFaction, color = MB10Colors.inkMuted)
                }
                Spacer(Modifier.height(6.dp))
                Text(
                    if (incoming) "Вызывает вас" else "Дозваниваемся...",
                    color = MB10Colors.inkFaint, fontFamily = JetBrainsMono, fontSize = 10.sp
                )
                Spacer(Modifier.height(22.dp))
                if (incoming) {
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlineButton("Принять", accentColor = MB10Colors.accentPrimary, onClick = onAccept)
                        OutlineButton("Отклонить", accentColor = MB10Colors.danger, onClick = onEnd)
                    }
                } else {
                    OutlineButton("Отменить вызов", accentColor = MB10Colors.danger, modifier = Modifier.fillMaxWidth(), onClick = onEnd)
                }
            }
        }
    }
}

/** Компактная плавающая плашка активного звонка — портрет 36×36 без сканлиний (на такой площади они не читаются), позывной, живой таймер, кнопка завершения. */
@Composable
private fun ActiveCallBar(state: CallUiState, onEnd: () -> Unit) {
    var elapsedSeconds by remember(state.callId) { mutableLongStateOf(0L) }
    LaunchedEffect(state.callId, state.startedAt) {
        while (true) {
            elapsedSeconds = ((System.currentTimeMillis() - state.startedAt) / 1000).coerceAtLeast(0)
            delay(1000)
        }
    }
    val minutes = elapsedSeconds / 60
    val seconds = elapsedSeconds % 60

    Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), contentAlignment = Alignment.TopCenter) {
        ChamferedPanel(
            borderColor = if (state.audioConnected) MB10Colors.accentPrimary else MB10Colors.accentBorder,
            fillColor = MB10Colors.bg1,
            cut = 8.dp,
            contentPadding = 10.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                HoloPortrait(letter = state.peerCallsign.take(1).uppercase(), portraitSize = 36.dp, showScanlines = false)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(state.peerCallsign, color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text(
                        "%d:%02d".format(minutes, seconds),
                        color = if (state.audioConnected) MB10Colors.inkMuted else MB10Colors.inkFaint,
                        fontFamily = JetBrainsMono, fontSize = 10.sp
                    )
                }
                Spacer(Modifier.width(10.dp))
                Box(
                    modifier = Modifier
                        .background(MB10Colors.danger, chamferShape(4.dp))
                        .clickable(onClick = onEnd)
                        .padding(horizontal = 14.dp, vertical = 8.dp)
                ) {
                    Text("ЗАВЕРШИТЬ", color = MB10Colors.onAccent, fontFamily = JetBrainsMono, fontSize = 10.sp)
                }
            }
        }
    }
}

@Composable
private fun HoloPortrait(letter: String, portraitSize: Dp, showScanlines: Boolean = true) {
    val cut = portraitSize * 0.12f
    Box(
        modifier = Modifier
            .size(portraitSize)
            .background(MB10Colors.bg2, chamferShape(cut))
            .border(1.dp, MB10Colors.accentPrimary, chamferShape(cut)),
        contentAlignment = Alignment.Center
    ) {
        Text(letter, color = MB10Colors.accentPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = (portraitSize.value * 0.4f).sp)
        if (showScanlines) {
            Canvas(Modifier.fillMaxSize()) {
                var y = 0f
                val gap = 6.dp.toPx()
                while (y < size.height) {
                    drawLine(Color.White.copy(alpha = 0.05f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
                    y += gap
                }
                val accentY = size.height * 0.32f
                drawLine(MB10Colors.accentPrimary.copy(alpha = 0.45f), Offset(0f, accentY), Offset(size.width, accentY), strokeWidth = 2f)
            }
        }
    }
}
