package com.megablok10.app.voice

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.PlaybackParams
import com.megablok10.app.log.Mb10Log
import java.io.File

private const val TAG = "VoicePlayer"

/**
 * `MediaPlayer` для одного голосового: динамик телефона (звук медиа), аудиофокус на время проигрывания (звонок или другое приложение забирает фокус — [onInterrupted]),
 * скорость через [PlaybackParams]. Все вызовы — с главного потока (так их шлёт [VoicePlayer] из скоупа процесса на Main); сбой плеера гасится и пишется в журнал.
 */
class AndroidClipPlayer(context: Context) : ClipPlayer {
    private val audio = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    override var onInterrupted: () -> Unit = {}
    override var onCompleted: () -> Unit = {}

    override fun play(file: File, startMs: Long, speed: Float): Boolean {
        release()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(ATTRS)
            .setOnAudioFocusChangeListener { change -> if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) onInterrupted() }
            .build()
        if (audio.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            Mb10Log.warnEvent(TAG, "voice.focus_denied")
            return false
        }
        focus = request
        val mp = MediaPlayer()
        return try {
            mp.setAudioAttributes(ATTRS)
            mp.setDataSource(file.absolutePath)
            mp.prepare()
            if (startMs > 0) mp.seekTo(startMs.toInt())
            mp.playbackParams = PlaybackParams().setSpeed(speed)
            mp.setOnCompletionListener { onCompleted() }
            mp.setOnErrorListener { _, what, extra ->
                Mb10Log.warnEvent(TAG, "voice.player_error", "what" to what, "extra" to extra)
                onCompleted()
                true
            }
            mp.start()
            player = mp
            true
        } catch (e: Exception) { // IOException (файл), IllegalStateException, IllegalArgumentException (скорость)
            Mb10Log.warnEvent(TAG, "voice.play_exception", "error" to e.javaClass.simpleName, "msg" to e.message)
            runCatching { mp.release() }
            abandon()
            false
        }
    }

    override fun pause() { runCatching { player?.pause() } }

    override fun resume() { runCatching { player?.start() } }

    override fun seekTo(ms: Long) { runCatching { player?.seekTo(ms.toInt()) } }

    override fun setSpeed(speed: Float) {
        val mp = player ?: return
        runCatching {
            val wasPlaying = mp.isPlaying
            mp.playbackParams = PlaybackParams().setSpeed(speed) // на части телефонов смена скорости запускает паузу — возвращаем состояние
            if (!wasPlaying) mp.pause()
        }
    }

    override fun positionMs(): Long = runCatching { player?.currentPosition?.toLong() }.getOrNull() ?: 0L

    override fun release() {
        player?.let { runCatching { it.stop() }; runCatching { it.release() } }
        player = null
        abandon()
    }

    private fun abandon() {
        focus?.let { audio.abandonAudioFocusRequest(it) }
        focus = null
    }

    private companion object {
        val ATTRS: AudioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    }
}
