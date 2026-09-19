package com.megablok10.app.sound

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

/**
 * Проигрывание синтезированных звуков взлома (см. [BreachTones]). Каждый звук рендерится один раз и лежит
 * в статическом AudioTrack; повторный play() перематывает его на начало. Любой сбой аудио молча глотается —
 * звук здесь украшение, он не должен ронять взлом.
 */
object BreachSfx {
    private const val PREFS = "sfx_prefs"
    private const val KEY_ENABLED = "breach_sfx"

    private val tracks = HashMap<BreachCue, AudioTrack>()

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun play(context: Context, cue: BreachCue) {
        if (!isEnabled(context)) return
        try {
            val track = synchronized(tracks) { tracks.getOrPut(cue) { buildTrack(BreachTones.render(cue)) } }
            track.stop()
            track.reloadStaticData()
            track.play()
        } catch (e: Exception) {
            // ни звука — ни проблемы
        }
    }

    private fun buildTrack(pcm: ShortArray): AudioTrack {
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            )
            .setAudioFormat(
                AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(BreachTones.SAMPLE_RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()
            )
            .setBufferSizeInBytes(pcm.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        track.write(pcm, 0, pcm.size)
        return track
    }
}
