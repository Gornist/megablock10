package com.megablok10.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbChamferForm
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.mbFrame
import com.megablok10.app.voice.AndroidClipRecorder
import com.megablok10.app.voice.RecordedClip
import com.megablok10.app.voice.RecordingState
import com.megablok10.app.voice.VoiceMarker
import com.megablok10.app.voice.VoiceRecordSession
import com.megablok10.app.voice.VoiceResult
import com.megablok10.app.voice.VoiceWaveform
import kotlinx.coroutines.delay
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

/** «0:07» для длительности в миллисекундах. */
internal fun formatVoiceDuration(ms: Long): String = "%d:%02d".format(ms / 60_000, ms / 1_000 % 60)

/** Волна голосового столбиками; [live] — последние замеры громкости при записи, иначе [bars] (0..255 на столбик). */
@Composable
internal fun VoiceWaveformView(bars: List<Float>, modifier: Modifier = Modifier, color: Color, dim: Color = color.copy(alpha = 0.35f), progress: Float = 1f) {
    Canvas(modifier.height(26.dp)) {
        if (bars.isEmpty()) return@Canvas
        val step = size.width / bars.size
        val barWidth = (step * 0.6f).coerceAtLeast(1.5f)
        bars.forEachIndexed { i, h ->
            val barHeight = (size.height * h.coerceIn(0.08f, 1f))
            val x = i * step + (step - barWidth) / 2
            drawRoundRect(
                color = if ((i + 0.5f) / bars.size <= progress) color else dim,
                topLeft = Offset(x, (size.height - barHeight) / 2),
                size = Size(barWidth, barHeight),
                cornerRadius = CornerRadius(barWidth / 2, barWidth / 2)
            )
        }
    }
}

internal fun barsOf(waveform: ByteArray): List<Float> = waveform.map { VoiceWaveform.height(it) }

/**
 * Голосовое сообщение в ленте. В этом PR — вид без воспроизведения (проигрыватель — следующий PR): значок микрофона, волна, длительность, время и отметка статуса.
 */
@Composable
internal fun VoiceBubble(msg: ChatMessageEntity, self: Boolean) {
    val voice = remember(msg.body) { VoiceMarker.parse(msg.body) } ?: return
    val c = LocalMbColors.current
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val mark = if (self) statusMark(msg.status) else null
    val meta = timeFormat.format(msg.timestamp) + (mark?.let { " ${it.first}" } ?: "")
    val ink = if (self) c.bubbleOwnText else c.bubbleInText
    val edge = if (self) c.bubbleOwnEdge else c.bubbleInEdge
    val fill = if (self) c.bubbleOwnFill else c.bubbleInFill
    Column(Modifier.widthIn(max = 280.dp), horizontalAlignment = if (self) Alignment.End else Alignment.Start) {
        Row(
            Modifier
                .mbFrame(fill = fill, edge = edge, form = MbChamferForm.Tab, cut = 8.dp)
                .padding(horizontal = 10.dp, vertical = 8.dp)
                .semantics { contentDescription = "Голосовое сообщение, ${formatVoiceDuration(voice.durationMs)}" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(painterResource(MbIcons.Mic), contentDescription = null, tint = ink, modifier = Modifier.size(20.dp))
            VoiceWaveformView(barsOf(voice.waveform), Modifier.width(120.dp), color = ink)
            Text(formatVoiceDuration(voice.durationMs), style = MbTypography.meta, color = ink)
        }
        Text(meta, style = MbTypography.meta, color = if (self) Color(0xFFA9E8C3) else c.ink2, modifier = Modifier.padding(top = 2.dp))
    }
}

/**
 * Запись голосового по образцу Telegram: удержание кнопки микрофона — запись, влево — отмена, вверх — закрепить (дальше без удержания, кнопки «Отмена»/«Отправить»).
 * Возвращает кнопку микрофона для [com.megablok10.app.ui.theme.MbComposer] и полосу записи ([RecordingBar]), которая заменяет поле ввода, пока идёт запись.
 */
internal class VoiceRecordUi(val recording: Boolean, val state: RecordingState, val micButton: @Composable () -> Unit, val send: () -> Unit, val cancel: () -> Unit)

@Composable
internal fun rememberVoiceRecordUi(micAllowed: Boolean, onClip: (RecordedClip) -> Unit): VoiceRecordUi {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val session = remember {
        val dir = File(context.cacheDir, "voice-rec")
        VoiceRecordSession(AndroidClipRecorder(context), { UUID.randomUUID().toString().replace("-", "").let { it to File(dir, "$it.m4a") } }, System::currentTimeMillis)
    }
    var recording by remember { mutableStateOf(false) }
    var state by remember { mutableStateOf(RecordingState()) }
    val currentOnClip = rememberUpdatedState(onClip)
    val micFree = rememberUpdatedState(micAllowed)
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}

    fun toast(text: String) = Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    fun handle(result: VoiceResult?) {
        if (result == null) return
        recording = false
        state = RecordingState()
        when (result) {
            is VoiceResult.Send -> currentOnClip.value(result.clip)
            VoiceResult.TooShort -> toast("Слишком короткое: удерживайте кнопку")
            VoiceResult.Failed -> toast("Запись не удалась")
            VoiceResult.Cancelled -> {}
        }
    }

    LaunchedEffect(recording) {
        while (recording) {
            delay(TICK_MS)
            val ended = session.tick()
            state = session.state
            if (ended != null) handle(ended)
        }
    }
    DisposableEffect(Unit) { onDispose { if (session.isRecording) session.cancel() } }

    val mic: @Composable () -> Unit = {
        val c = LocalMbColors.current
        Box(
            Modifier
                .size(MbDimens.rowHeight)
                .mbFrame(fill = if (micFree.value) c.acc else c.plate, edge = if (micFree.value) c.acc else c.plateEdge, form = MbChamferForm.Std, cut = 8.dp)
                .semantics { contentDescription = "Голосовое сообщение: удерживайте для записи" }
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        if (!micFree.value) { toast("Во время звонка запись недоступна"); return@awaitEachGesture }
                        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            permission.launch(Manifest.permission.RECORD_AUDIO)
                            return@awaitEachGesture
                        }
                        if (!session.start()) { toast("Не удалось начать запись"); return@awaitEachGesture }
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        recording = true
                        state = session.state
                        var wasLocked = false
                        do {
                            val change = awaitPointerEvent().changes.first()
                            val delta = change.position - down.position
                            session.onDrag(delta.x, delta.y)
                            state = session.state
                            if (state.locked && !wasLocked) { wasLocked = true; haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
                        } while (change.pressed)
                        handle(session.release())
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Icon(painterResource(MbIcons.Mic), contentDescription = null, tint = if (micFree.value) c.accInk else c.ink3, modifier = Modifier.size(20.dp))
        }
    }
    return VoiceRecordUi(recording, state, mic, send = { handle(session.sendLocked()) }, cancel = { handle(session.cancel()) })
}

private const val TICK_MS = 100L

/** Полоса записи на месте поля ввода: красная точка, время, живая волна и подсказка жеста; у закреплённой записи — «Отмена» и «Отправить». */
@Composable
internal fun RecordingBar(state: RecordingState, onSend: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    val warn = state.willCancel
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MbDimens.rowHeight)
            .mbFrame(fill = Color(0xFF140D10), edge = if (warn) c.bad else Color(0xFF6B3337), form = MbChamferForm.Tab, cut = 8.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(Modifier.size(10.dp).mbFrame(fill = c.bad, edge = c.bad, form = MbChamferForm.Std, cut = 2.dp))
        Text(formatVoiceDuration(state.elapsedMs), style = MbTypography.dialogText, color = c.ink)
        VoiceWaveformView(
            bars = state.recent.map { (it / 32_767f).coerceIn(0f, 1f).let { v -> Math.sqrt(v.toDouble()).toFloat() } },
            modifier = Modifier.weight(1f),
            color = if (warn) c.bad else c.acc,
        )
        if (state.locked) {
            MbButton("Отмена", onClick = onCancel, kind = MbButtonKind.Danger, inline = true)
            MbButton("Отправить", onClick = onSend, kind = MbButtonKind.Success, inline = true)
        } else {
            Text(if (warn) "отпустите — отмена" else "← отмена  ↑ закрепить", style = MbTypography.meta, color = if (warn) c.bad else c.ink3)
        }
    }
}
