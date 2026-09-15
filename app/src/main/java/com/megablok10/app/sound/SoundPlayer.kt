package com.megablok10.app.sound

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import com.megablok10.app.R

/**
 * Два разных способа проигрывания звука нужны для двух разных сценариев:
 * SoundPool — для короткого "пинга" сообщения (низкая задержка, не жаль
 * пересоздать); MediaPlayer с loop=true — для гудка/рингтона звонка, которые
 * должны крутиться, пока не наступит явное событие (ответили/сбросили) и не
 * укладываются в модель SoundPool с её лимитом на длину сэмпла.
 */
object SoundPlayer {
    private var soundPool: SoundPool? = null
    private var messageSoundId: Int = 0
    private var messageSoundReady = false
    private var loopPlayer: MediaPlayer? = null

    /**
     * SoundPool.load() декодирует файл асинхронно — play() сразу после load()
     * молча ничего не делает (SoundPool: "play soundID N not READY"), это
     * поймано вживую при первом же тестовом сообщении. Поэтому прогреваем
     * пул заранее (из ChatStore.start, до того как реально может прийти
     * сообщение) и ждём onLoadComplete, а не первого вызова play().
     */
    fun preload(context: Context) {
        if (soundPool != null) return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val pool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attrs).build()
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0 && sampleId == messageSoundId) messageSoundReady = true
        }
        messageSoundId = pool.load(context.applicationContext, R.raw.cyberpunk_message, 1)
        soundPool = pool
    }

    /** Короткий сигнал полученного сообщения — самообороны от своих же исходящих не требует, вызывающий код сам решает, когда звать. */
    fun playMessageReceived(context: Context) {
        preload(context)
        val pool = soundPool ?: return
        if (messageSoundReady) pool.play(messageSoundId, 1f, 1f, 1, 0, 1f)
    }

    /** Гудок дозвона — крутится, пока исходящий вызов не примут/не сбросят/не отменят. */
    fun startDialTone(context: Context) = startLoop(context, R.raw.cp77_dial_tone)

    /** Рингтон входящего звонка — крутится до принятия/отклонения/таймаута. */
    fun startIncomingRingtone(context: Context) = startLoop(context, R.raw.cyberpunk_ring)

    private fun startLoop(context: Context, resId: Int) {
        stopLoop()
        val player = MediaPlayer.create(context.applicationContext, resId) ?: return
        player.isLooping = true
        player.start()
        loopPlayer = player
    }

    /** Останавливает гудок/рингтон, если сейчас крутится — безопасно звать в любой момент, в т.ч. если ничего не играет. */
    fun stopLoop() {
        loopPlayer?.let {
            try {
                if (it.isPlaying) it.stop()
            } catch (e: IllegalStateException) {
                // плеер мог уже быть в невалидном состоянии — не критично, всё равно release
            }
            it.release()
        }
        loopPlayer = null
    }
}
