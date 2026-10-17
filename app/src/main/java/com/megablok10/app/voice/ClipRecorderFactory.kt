package com.megablok10.app.voice

import android.content.Context
import com.megablok10.app.call.CallDenoise
import com.megablok10.app.call.RnNoiseNative
import com.megablok10.app.log.Mb10Log
import java.io.File

/**
 * Выбор рекордера голосового — в одном месте. С шумодавом ([DenoisedClipRecorder]) — если библиотека RNNoise загрузилась, выключатель [CallDenoise.enabled] не снят и
 * состояние сети создаётся; иначе прежний [AndroidClipRecorder] (MediaRecorder). Формат файла у обоих один.
 */
internal fun pickClipRecorder(nativeAvailable: Boolean, enabled: Boolean, engineUsable: () -> Boolean, denoised: () -> ClipRecorder, plain: () -> ClipRecorder): ClipRecorder =
    if (nativeAvailable && enabled && engineUsable()) denoised() else plain()

/** Рекордер для экрана: выбор делается на каждом старте записи, чтобы выключатель в отладке действовал без пересоздания экрана. */
fun createClipRecorder(context: Context): ClipRecorder = SelectingClipRecorder(
    choose = {
        pickClipRecorder(
            nativeAvailable = RnNoiseNative.available,
            enabled = CallDenoise.enabled,
            engineUsable = { RnNoiseNative.create().also { if (it != 0L) RnNoiseNative.destroy(it) } != 0L },
            denoised = { DenoisedClipRecorder() },
            plain = { AndroidClipRecorder(context) },
        )
    },
    fallback = { failed -> if (failed is DenoisedClipRecorder) AndroidClipRecorder(context) else null },
)

/**
 * Берёт рекордер у [choose] на каждом [start] и дальше работает с ним до [stop]/[cancel]. Не стартовал рекордер с шумодавом
 * (кодек конкретного телефона не принял формат, AudioRecord не открылся) — [fallback] даёт прежний рекордер: голосовые не должны
 * пропасть из-за новой ветки. Занятый микрофон (звонок) остаётся `false` и там, и там.
 */
internal class SelectingClipRecorder(
    private val choose: () -> ClipRecorder,
    private val fallback: (failed: ClipRecorder) -> ClipRecorder? = { null },
) : ClipRecorder {
    private var current: ClipRecorder? = null

    override fun start(file: File): Boolean {
        current?.cancel()
        val r = choose()
        current = r
        if (r.start(file)) return true
        val plain = fallback(r) ?: return false
        Mb10Log.warnEvent("VoiceRecorder", "voice.record_fallback", "from" to r.javaClass.simpleName)
        current = plain
        return plain.start(file)
    }

    override fun maxAmplitude(): Int = current?.maxAmplitude() ?: 0

    override fun stop(): Boolean = current?.stop() ?: false

    override fun cancel() {
        current?.cancel()
    }
}
