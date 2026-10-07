package com.megablok10.app.voice

import com.megablok10.app.log.Mb10Log
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch

private const val TAG = "VoicePlayer"

/** Воспроизведение одного файла (на устройстве — `MediaPlayer`, в тестах — подмена). */
interface ClipPlayer {
    /** Системе нужен звук (звонок, другое приложение) — проигрывание надо поставить на паузу. Назначает [VoicePlayer]. */
    var onInterrupted: () -> Unit
    /** Файл дошёл до конца. */
    var onCompleted: () -> Unit
    /** false — файл не открылся. Начинает с [startMs] на скорости [speed]. */
    fun play(file: File, startMs: Long, speed: Float): Boolean
    fun pause()
    fun resume()
    fun seekTo(ms: Long)
    fun setSpeed(speed: Float)
    fun positionMs(): Long
    fun release()
}

/** Одно голосовое в ленте: строка Room и файл. [incoming] — чужое (у него бывает «не прослушано»). */
data class VoiceTrack(val rowId: Long, val clipId: String, val durationMs: Long, val peerKey: String, val incoming: Boolean, val timestamp: Long)

/** Что играет сейчас: [track] null — тишина. */
data class PlayerState(val track: VoiceTrack? = null, val playing: Boolean = false, val positionMs: Long = 0, val speed: Float = 1f)

/**
 * Проигрыватель голосовых по образцу Telegram: один на приложение (живёт в AppGraph — выход из треда его не обрывает), играет одно сообщение, поверх запускается
 * другое — прежнее останавливается. Скорость 1×/1,5×/2× запоминается между сообщениями. Входящее помечается прослушанным в момент старта ([markListened] → точка «не прослушано»
 * гаснет); по окончании при включённом автопроигрывании ([autoplay]) идёт следующее непрослушанное входящее от того же собеседника ([nextUnlistened]). Звонок и потеря аудиофокуса
 * ставят на паузу, начало записи ([stop]) — останавливают.
 */
class VoicePlayer(
    private val engine: ClipPlayer,
    private val store: VoiceStore,
    private val scope: CoroutineScope,
    private val markListened: suspend (rowId: Long) -> Unit,
    /** Следующее непрослушанное входящее от [peerKey] после [afterTimestamp]; null — больше нет. */
    private val nextUnlistened: suspend (peerKey: String, afterTimestamp: Long) -> VoiceTrack?,
    private val autoplay: () -> Boolean,
) {
    private val _state = MutableStateFlow(PlayerState())
    val state: StateFlow<PlayerState> = _state.asStateFlow()
    private var ticker: Job? = null
    private var callWatch: Job? = null

    init {
        engine.onCompleted = { scope.launch { onFinished() } }
        engine.onInterrupted = { pause() }
    }

    /** Остановить проигрывание при начале звонка (из корня: поток событий звонка). Повторный вызов (новая сессия) заменяет прежнюю подписку. */
    fun stopDuring(callActive: Flow<Boolean>): Job {
        callWatch?.cancel()
        return scope.launch { callActive.distinctUntilChanged().filter { it }.collect { stop() } }.also { callWatch = it }
    }

    /** Нажатие на кнопку пузыря: играет это — пауза, на паузе — дальше, иначе — сначала. */
    fun toggle(track: VoiceTrack) {
        val s = _state.value
        when {
            s.track?.rowId == track.rowId && s.playing -> pause()
            s.track?.rowId == track.rowId -> resume()
            else -> scope.launch { start(track, 0) }
        }
    }

    /** Нажатие на волну: перемотка (если это сообщение не играет — начать с этого места). */
    fun seek(track: VoiceTrack, fraction: Float) {
        val ms = (track.durationMs * fraction.coerceIn(0f, 1f)).toLong()
        if (_state.value.track?.rowId == track.rowId) {
            engine.seekTo(ms)
            _state.value = _state.value.copy(positionMs = ms)
        } else {
            scope.launch { start(track, ms) }
        }
    }

    fun cycleSpeed() {
        val next = nextSpeed(_state.value.speed)
        engine.setSpeed(next)
        _state.value = _state.value.copy(speed = next)
    }

    fun pause() {
        if (!_state.value.playing) return
        engine.pause()
        ticker?.cancel()
        _state.value = _state.value.copy(playing = false, positionMs = engine.positionMs())
    }

    /** [stop] из любого потока (сброс персонажа идёт не с главного): выполняется в скоупе плеера. */
    fun requestStop() { scope.launch { stop() } }

    fun stop() {
        if (_state.value.track == null) return
        ticker?.cancel()
        engine.release()
        _state.value = PlayerState(speed = _state.value.speed)
    }

    private fun resume() {
        engine.resume()
        _state.value = _state.value.copy(playing = true)
        startTicker()
    }

    private suspend fun start(track: VoiceTrack, startMs: Long) {
        val file = store.file(track.clipId)?.takeIf { it.isFile }
        stop()
        if (file == null || !engine.play(file, startMs, _state.value.speed)) {
            Mb10Log.warnEvent(TAG, "voice.play_failed", "clip" to track.clipId.take(8), "fileExists" to (file != null))
            return
        }
        _state.value = _state.value.copy(track = track, playing = true, positionMs = startMs)
        startTicker()
        if (track.incoming) markListened(track.rowId)
        Mb10Log.event(TAG, "voice.play", "clip" to track.clipId.take(8), "incoming" to track.incoming, "fromMs" to startMs, "speed" to _state.value.speed)
    }

    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (true) {
                delay(TICK_MS)
                _state.value = _state.value.copy(positionMs = engine.positionMs())
            }
        }
    }

    private suspend fun onFinished() {
        val finished = _state.value.track
        ticker?.cancel()
        engine.release()
        _state.value = PlayerState(speed = _state.value.speed)
        // Журнал: что было дальше с автопроигрыванием — по нему на живом телефоне видно, почему следующее не пошло (нет следующего, выключено, своё сообщение).
        if (finished == null) return
        val reason = when {
            !finished.incoming -> "own"
            !autoplay() -> "off"
            else -> null
        }
        val next = if (reason == null) nextUnlistened(finished.peerKey, finished.timestamp) else null
        Mb10Log.event(TAG, "voice.finished", "clip" to finished.clipId.take(8), "autoplay" to (reason ?: "on"), "next" to (next?.clipId?.take(8) ?: "none"))
        next?.let { start(it, 0) }
    }

    companion object {
        const val TICK_MS = 100L
        val SPEEDS = listOf(1f, 1.5f, 2f)

        fun nextSpeed(current: Float): Float = SPEEDS[(SPEEDS.indexOf(current).takeIf { it >= 0 } ?: 0).plus(1) % SPEEDS.size]

        fun speedLabel(speed: Float): String = if (speed == 1f) "1×" else if (speed == 2f) "2×" else "1,5×"
    }
}
