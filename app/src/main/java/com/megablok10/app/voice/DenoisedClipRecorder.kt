package com.megablok10.app.voice

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Process
import com.megablok10.app.call.FrameDenoiser
import com.megablok10.app.call.RnNoiseNative
import com.megablok10.app.log.Mb10Log
import java.io.File
import kotlin.math.roundToInt

private const val TAG = "VoiceRecorder"
private const val CODEC_TIMEOUT_US = 10_000L
private const val CODEC_MAX_WAIT_ROUNDS = 500
private const val JOIN_TIMEOUT_MS = 5_000L
private const val BYTES_PER_SAMPLE = 2

/**
 * Запись голосового через RNNoise: микрофон (AudioRecord, 48 кГц моно) → [ClipPcmPipeline] (шумодав + 48→16 кГц) → кодек AAC-LC → MPEG-4 (`.m4a`). Файл тот же, что у
 * [AndroidClipRecorder]: AAC-LC, моно, 16 кГц, 20 кбит/с — получатели и сервер разницы не видят. Не открылся микрофон (занят звонком, нет разрешения) или кодек — [start] = false,
 * всё закрыто; молча на MediaRecorder он не откатывается (это решает [createClipRecorder] до старта). Сбой потока записи — `voice.record_failed`, [stop] = false, файл удалён.
 * Свой жёсткий предел — [VoiceLimits.MAX_DURATION_MS] + 1 с (штатно запись останавливает [VoiceRecordSession]).
 */
class DenoisedClipRecorder(private val engine: FrameDenoiser = RnNoiseNative) : ClipRecorder {
    private var session: Session? = null

    @SuppressLint("MissingPermission") // разрешение проверяет экран до старта; без него AudioRecord не откроется — это штатный false
    override fun start(file: File): Boolean {
        cancel()
        file.parentFile?.mkdirs()
        val s = Session(file, engine)
        return try {
            s.open()
            s.begin()
            session = s
            Mb10Log.event(TAG, "voice.record_start", "file" to file.name, "denoise" to if (s.pipeline.denoising) "on" else "off")
            true
        } catch (e: Exception) { // SecurityException / IllegalStateException / IOException / RuntimeException: микрофон занят, нет разрешения, кодек не создался
            Mb10Log.warnEvent(TAG, "voice.record_failed", "error" to e.javaClass.simpleName, "msg" to e.message)
            s.close()
            file.delete()
            false
        }
    }

    override fun maxAmplitude(): Int = session?.pipeline?.takePeak() ?: 0

    override fun stop(): Boolean {
        val s = session ?: return false
        session = null
        return s.finish()
    }

    override fun cancel() {
        val s = session ?: return
        session = null
        s.abort()
    }

    /** Одна запись: ресурсы, поток и счётчики. Всё закрывается в [close]; поток сам завершает кодек и контейнер на остановке. */
    private class Session(private val file: File, engine: FrameDenoiser) {
        val pipeline = ClipPcmPipeline(engine, ::encode)
        private var audio: AudioRecord? = null
        private var codec: MediaCodec? = null
        private var muxer: MediaMuxer? = null
        private var thread: Thread? = null
        private var track = -1
        private var muxerStarted = false
        private var muxerStopped = false
        private var fedSamples = 0L
        private var bytesWritten = 0L
        private val info = MediaCodec.BufferInfo()

        @Volatile private var stopRequested = false
        @Volatile private var cancelled = false
        @Volatile private var failed = false

        @SuppressLint("MissingPermission")
        fun open() {
            val min = AudioRecord.getMinBufferSize(ClipPcmPipeline.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(min > 0) { "no_audio_buffer" }
            val rec = AudioRecord(
                MediaRecorder.AudioSource.MIC, ClipPcmPipeline.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(min * 2, ClipPcmPipeline.FRAME * BYTES_PER_SAMPLE * 8),
            )
            audio = rec
            check(rec.state == AudioRecord.STATE_INITIALIZED) { "audio_not_initialized" }
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, VoiceLimits.SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, VoiceLimits.BITRATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, ENCODER_INPUT_BYTES)
            }
            val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec = c
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            c.start()
            muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        }

        /** Включает микрофон и запускает поток; занятый микрофон (звонок) — исключение, то есть [DenoisedClipRecorder.start] = false. */
        fun begin() {
            val rec = checkNotNull(audio)
            rec.startRecording()
            check(rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "mic_busy" }
            thread = Thread({ record() }, "voice-record").also { it.start() }
        }

        /** Остановить и дописать файл; true — файл валиден. */
        fun finish(): Boolean {
            stopRequested = true
            joinThread()
            return !failed && !cancelled && bytesWritten > 0
        }

        /** Остановить и выбросить файл. */
        fun abort() {
            cancelled = true
            stopRequested = true
            joinThread()
            file.delete()
        }

        private fun joinThread() {
            val t = thread ?: return
            t.join(JOIN_TIMEOUT_MS)
            if (t.isAlive) failed = true
        }

        private fun record() {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val startedAt = System.nanoTime()
            try {
                readLoop()
                if (!cancelled) finalizeFile()
            } catch (e: Exception) {
                failed = true
                Mb10Log.warnEvent(TAG, "voice.record_failed", "error" to e.javaClass.simpleName, "msg" to e.message)
            } finally {
                val denoise = pipeline.denoising
                val speech = pipeline.speechProbMean
                close()
                if (failed) file.delete() else if (!cancelled) logStop(startedAt, denoise, speech)
            }
        }

        private fun readLoop() {
            val rec = checkNotNull(audio)
            val buf = ShortArray(ClipPcmPipeline.FRAME)
            val limitSamples = (VoiceLimits.MAX_DURATION_MS + 1_000) * VoiceLimits.SAMPLE_RATE / 1_000
            while (!stopRequested && fedSamples < limitSamples) {
                val n = rec.read(buf, 0, buf.size)
                check(n >= 0) { "audio_read_$n" }
                if (n > 0) pipeline.push(buf, n)
            }
        }

        private fun logStop(startedAt: Long, denoise: Boolean, speech: Double) {
            Mb10Log.event(
                TAG, "voice.record_stop",
                "durationMs" to fedSamples * 1_000 / VoiceLimits.SAMPLE_RATE,
                "bytes" to file.length(),
                "speechProbMean" to (speech * 1_000).roundToInt() / 1_000.0,
                "denoise" to if (denoise) "on" else "off",
                "wallMs" to (System.nanoTime() - startedAt) / 1_000_000,
            )
        }

        /** Блок 16 кГц от [pipeline] → кодек. */
        private fun encode(samples: ShortArray, count: Int) {
            val c = checkNotNull(codec)
            val bytes = ByteArray(count * BYTES_PER_SAMPLE)
            for (i in 0 until count) {
                bytes[i * 2] = samples[i].toInt().toByte()
                bytes[i * 2 + 1] = (samples[i].toInt() shr 8).toByte()
            }
            var off = 0
            var rounds = 0
            while (off < bytes.size) {
                val idx = c.dequeueInputBuffer(CODEC_TIMEOUT_US)
                if (idx < 0) {
                    check(++rounds < CODEC_MAX_WAIT_ROUNDS) { "codec_input_stuck" }
                    drain(false)
                } else {
                    val ib = checkNotNull(c.getInputBuffer(idx))
                    ib.clear()
                    val len = minOf(bytes.size - off, ib.remaining()) and 1.inv()
                    ib.put(bytes, off, len)
                    c.queueInputBuffer(idx, 0, len, fedSamples * 1_000_000L / VoiceLimits.SAMPLE_RATE, 0)
                    fedSamples += len / BYTES_PER_SAMPLE
                    off += len
                }
            }
            drain(false)
        }

        /** Конец потока: EOS в кодек, дочитать его выход, закрыть контейнер. Без единого кадра на выходе файла нет — [failed]. */
        private fun finalizeFile() {
            val c = checkNotNull(codec)
            var idx = c.dequeueInputBuffer(CODEC_TIMEOUT_US)
            var rounds = 0
            while (idx < 0) {
                check(++rounds < CODEC_MAX_WAIT_ROUNDS) { "codec_eos_stuck" }
                drain(false)
                idx = c.dequeueInputBuffer(CODEC_TIMEOUT_US)
            }
            c.queueInputBuffer(idx, 0, 0, fedSamples * 1_000_000L / VoiceLimits.SAMPLE_RATE, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
            check(muxerStarted && bytesWritten > 0) { "no_audio_frames" }
            checkNotNull(muxer).stop()
            muxerStopped = true
        }

        /** Выход кодека → контейнер. [untilEos] — ждать конец потока; иначе забрать, что готово. */
        private fun drain(untilEos: Boolean) {
            val c = checkNotNull(codec)
            var done = false
            var idle = 0
            while (!done) {
                val idx = c.dequeueOutputBuffer(info, if (untilEos) CODEC_TIMEOUT_US else 0)
                if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    idle++
                    check(idle < CODEC_MAX_WAIT_ROUNDS) { "codec_output_stuck" }
                    done = !untilEos
                } else if (idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val m = checkNotNull(muxer)
                    track = m.addTrack(c.outputFormat)
                    m.start()
                    muxerStarted = true
                } else if (idx >= 0) {
                    idle = 0
                    writeSample(c, idx)
                    done = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                }
            }
        }

        private fun writeSample(c: MediaCodec, idx: Int) {
            val ob = checkNotNull(c.getOutputBuffer(idx))
            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && muxerStarted) {
                ob.position(info.offset)
                ob.limit(info.offset + info.size)
                checkNotNull(muxer).writeSampleData(track, ob, info)
                bytesWritten += info.size
            }
            c.releaseOutputBuffer(idx, false)
        }

        /** Освободить всё; безопасно звать в любом состоянии и повторно. */
        fun close() {
            audio?.let { runCatching { it.stop() }; runCatching { it.release() } }
            audio = null
            codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
            codec = null
            val m = muxer
            if (m != null) {
                if (muxerStarted && !muxerStopped) runCatching { m.stop() }
                runCatching { m.release() }
            }
            muxer = null
            pipeline.release()
        }

        companion object {
            const val ENCODER_INPUT_BYTES = 8_192
        }
    }
}
