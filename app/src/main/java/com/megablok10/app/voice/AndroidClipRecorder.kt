package com.megablok10.app.voice

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import com.megablok10.app.log.Mb10Log
import java.io.File

private const val TAG = "VoiceRecorder"

/**
 * Запись голосового: AAC-LC, моно, 16 кГц, 20 кбит/с в MPEG-4 (`.m4a`) — работает на всех Android ≥ 8; 60 с ≈ 150 КБ ([VoiceLimits]). Источник — обычный микрофон (MIC):
 * обработку речи для звонков делает WebRTC, голосовому она не нужна. Предел по времени [VoiceLimits.MAX_DURATION_MS] стоит и у самого рекордера — страховка, если экран
 * не вызовет [VoiceRecordSession.tick].
 */
class AndroidClipRecorder(private val context: Context) : ClipRecorder {
    private var recorder: MediaRecorder? = null

    override fun start(file: File): Boolean {
        release()
        file.parentFile?.mkdirs()
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        return try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioSamplingRate(VoiceLimits.SAMPLE_RATE)
            r.setAudioEncodingBitRate(VoiceLimits.BITRATE)
            r.setMaxDuration((VoiceLimits.MAX_DURATION_MS + 1_000).toInt())
            r.setOutputFile(file.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            Mb10Log.event(TAG, "voice.record_start", "file" to file.name)
            true
        } catch (e: Exception) { // IllegalStateException / IOException / RuntimeException: микрофон занят, нет разрешения
            Mb10Log.warnEvent(TAG, "voice.record_failed", "error" to e.javaClass.simpleName, "msg" to e.message)
            runCatching { r.release() }
            false
        }
    }

    override fun maxAmplitude(): Int = try { recorder?.maxAmplitude ?: 0 } catch (e: IllegalStateException) { 0 }

    override fun stop(): Boolean {
        val r = recorder ?: return false
        recorder = null
        return try {
            r.stop()
            true
        } catch (e: RuntimeException) { // stop() бросает, если записано слишком мало: файл невалиден
            Mb10Log.warnEvent(TAG, "voice.record_stop_failed", "error" to e.javaClass.simpleName)
            false
        } finally {
            runCatching { r.release() }
        }
    }

    override fun cancel() = release()

    private fun release() {
        val r = recorder ?: return
        recorder = null
        runCatching { r.stop() }
        runCatching { r.release() }
    }
}
