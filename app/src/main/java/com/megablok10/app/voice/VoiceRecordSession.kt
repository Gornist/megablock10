package com.megablok10.app.voice

import java.io.File

/** Запись звука в файл (на устройстве — `MediaRecorder`, в тестах — подмена). */
interface ClipRecorder {
    /** false — микрофон занят или не открылся (идёт звонок, нет разрешения). */
    fun start(file: File): Boolean
    /** Громкость с прошлого вызова, 0..32767. */
    fun maxAmplitude(): Int
    /** Остановить и закрыть файл; false — запись не получилась (слишком короткая, сбой кодека). */
    fun stop(): Boolean
    /** Остановить и выбросить. */
    fun cancel()
}

class RecordedClip(val id: String, val file: File, val durationMs: Long, val waveform: ByteArray)

/** Что делает палец на кнопке микрофона: по смещению от точки нажатия. */
enum class VoiceGesture { HOLD, CANCEL, LOCK }

/** Состояние записи для экрана. */
data class RecordingState(
    val elapsedMs: Long = 0,
    /** Закреплена свайпом вверх: палец можно отпустить, отправка и отмена — кнопками. */
    val locked: Boolean = false,
    /** Палец ушёл влево дальше порога: при отпускании запись отменится. */
    val willCancel: Boolean = false,
    /** Последние замеры громкости для «живой» волны на экране. */
    val recent: List<Int> = emptyList(),
)

/** Итог отпускания кнопки или нажатия «Отправить» / «Отмена». */
sealed class VoiceResult {
    class Send(val clip: RecordedClip) : VoiceResult()
    object Cancelled : VoiceResult()
    /** Короче [VoiceRecordSession.MIN_MS]: случайное касание, не отправляем (как в Telegram). */
    object TooShort : VoiceResult()
    object Failed : VoiceResult()
}

/**
 * Одна запись голосового по образцу Telegram: удержание — запись, смахнуть влево — отмена, вверх — закрепить (дальше без удержания), предел [VoiceLimits.MAX_DURATION_MS].
 * Без Android: рекордер ([ClipRecorder]), часы и источник файлов приходят снаружи, экран лишь пересылает жесты ([onDrag], [release]) и зовёт [tick] раз в ~100 мс.
 */
class VoiceRecordSession(
    private val recorder: ClipRecorder,
    private val newClip: () -> Pair<String, File>,
    private val now: () -> Long,
    /** Порог смещения (пиксели), после которого жест считается отменой или закреплением. */
    private val thresholdPx: Float = DEFAULT_THRESHOLD_PX,
) {
    private var id = ""
    private var file: File? = null
    private var startedAt = 0L
    private val samples = mutableListOf<Int>()
    private var recording = false
    var state = RecordingState()
        private set

    val isRecording get() = recording

    /** false — запись не началась (рекордер отказал). */
    fun start(): Boolean {
        if (recording) return true
        val (clipId, clipFile) = newClip()
        if (!recorder.start(clipFile)) return false
        id = clipId; file = clipFile; startedAt = now(); samples.clear(); recording = true
        state = RecordingState()
        return true
    }

    /** Смещение пальца от точки нажатия ([dx] вправо, [dy] вниз — как в Compose). Закрепление необратимо, отмену можно вернуть, отведя палец обратно. */
    fun onDrag(dx: Float, dy: Float) {
        if (!recording || state.locked) return
        val gesture = classify(dx, dy, thresholdPx)
        state = state.copy(locked = gesture == VoiceGesture.LOCK, willCancel = gesture == VoiceGesture.CANCEL)
    }

    /** Раз в ~100 мс: замер громкости и проверка предела. Вернёт [VoiceResult.Send] — предел достигнут, запись завершена и её надо отправить. */
    fun tick(): VoiceResult? {
        if (!recording) return null
        samples += recorder.maxAmplitude()
        val elapsed = now() - startedAt
        state = state.copy(elapsedMs = elapsed, recent = samples.takeLast(RECENT_BARS))
        return if (elapsed >= VoiceLimits.MAX_DURATION_MS) finish(send = true) else null
    }

    /** Палец отпущен. Закреплённую запись это не трогает (null), иначе — итог по месту, где отпустили. */
    fun release(): VoiceResult? {
        if (!recording || state.locked) return null
        return finish(send = !state.willCancel)
    }

    /** Кнопка «Отправить» закреплённой записи. */
    fun sendLocked(): VoiceResult = if (recording) finish(send = true) else VoiceResult.Cancelled

    /** Кнопка «Отмена» или выход с экрана посреди записи. */
    fun cancel(): VoiceResult {
        if (recording) finish(send = false)
        return VoiceResult.Cancelled
    }

    private fun finish(send: Boolean): VoiceResult {
        recording = false
        val elapsed = now() - startedAt
        val target = file
        state = RecordingState()
        if (!send || target == null) {
            recorder.cancel(); target?.delete()
            return VoiceResult.Cancelled
        }
        if (elapsed < MIN_MS) {
            recorder.cancel(); target.delete()
            return VoiceResult.TooShort
        }
        if (!recorder.stop() || !validSize(target)) {
            target.delete()
            return VoiceResult.Failed
        }
        return VoiceResult.Send(RecordedClip(id, target, elapsed.coerceAtMost(VoiceLimits.MAX_DURATION_MS), VoiceWaveform.bars(samples)))
    }

    private fun validSize(file: File): Boolean = file.isFile && file.length() in 1..VoiceLimits.MAX_AUDIO_BYTES.toLong()

    companion object {
        const val MIN_MS = 1_000L
        const val DEFAULT_THRESHOLD_PX = 120f
        const val RECENT_BARS = 40

        /** Преобладающее направление смещения: влево дальше порога — отмена, вверх — закрепить; по диагонали выигрывает большее смещение. */
        fun classify(dx: Float, dy: Float, threshold: Float): VoiceGesture {
            val left = -dx
            val up = -dy
            return when {
                up >= threshold && up >= left -> VoiceGesture.LOCK
                left >= threshold -> VoiceGesture.CANCEL
                else -> VoiceGesture.HOLD
            }
        }
    }
}
