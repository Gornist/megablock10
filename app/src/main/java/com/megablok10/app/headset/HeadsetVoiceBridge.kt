package com.megablok10.app.headset

import com.megablok10.app.call.CallControls
import com.megablok10.app.call.CallPhase
import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Голос звонка в очках (срез 3 плана docs/netrun-phone-link.md): переносит микрофон и динамик идущего звонка на очки и возвращает на телефон,
 * если очки замолчали, сняты или отказались. Работает за отдельным переключателем (`enabled`), по умолчанию выключенным.
 *
 * Порядок: звонок ушёл в `IN_CALL` → очкам `voice{on:true}` (ARMED) → очки открыли микрофон и динамик и ответили `voice_ready{on:true}` (ACTIVE: маршрут
 * включён, пошли бинарные кадры) → при конце звонка, `voice_ready{on:false}`, тишине кадров микрофона дольше [SILENCE_MS] или обрыве канала — маршрут
 * выключается, очкам `voice{on:false}`. После возврата в этом же звонке голос в очки не переключается заново (FALLBACK до конца звонка): не дёргать
 * звук туда-сюда.
 *
 * Все изменения состояния — под одной блокировкой: события приходят из нескольких потоков (состояние звонка, команды очков, сетевой поток кадров).
 */
class HeadsetVoiceBridge(
    private val calls: CallControls,
    private val audio: VoiceAudioPort,
    private val enabled: () -> Boolean,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    enum class State { OFF, ARMED, ACTIVE, FALLBACK }

    @Volatile var state = State.OFF; private set

    private var send: (HeadsetOut) -> Boolean = { false }
    private var sendBinary: (ByteArray) -> Boolean = { false }
    private var armedAt = 0L
    private var lastMicAt = 0L
    private var lastSeq = -1L
    private var outSeq = 0L
    private var lost = 0L

    /** Следит за звонком и за живостью кадров микрофона, пока жив [scope] (соединение с очками). */
    fun observe(scope: CoroutineScope, send: (HeadsetOut) -> Boolean, sendBinary: (ByteArray) -> Boolean) {
        synchronized(this) {
            this.send = send
            this.sendBinary = sendBinary
        }
        scope.launch { calls.state.map { it.phase == CallPhase.IN_CALL }.distinctUntilChanged().collect { if (it) arm() else release("call_end") } }
        scope.launch { calls.state.map { it.muted }.distinctUntilChanged().collect { audio.setMuted(it) } }
        scope.launch {
            while (isActive) {
                delay(TICK_MS)
                tick()
            }
        }
    }

    /** Соединение с очками закончилось: голос возвращается телефону. */
    fun stop() = release("link_lost")

    fun handle(cmd: HeadsetCommand): Boolean {
        if (cmd !is HeadsetCommand.VoiceReady) return false
        synchronized(this) {
            when {
                cmd.on && state == State.ARMED -> activate()
                !cmd.on && (state == State.ARMED || state == State.ACTIVE) -> fallback("glasses_off")
            }
        }
        return true
    }

    /** Бинарный кадр от очков; не-голос и мусор молча игнорируются. */
    fun onBinary(bytes: ByteArray) {
        val frame = HeadsetVoiceCodec.decode(bytes)?.takeIf { it.type == HeadsetVoiceCodec.TYPE_MIC } ?: return
        synchronized(this) {
            if (state != State.ACTIVE) return
            if (lastSeq >= 0 && frame.seq != lastSeq + 1) lost += (frame.seq - lastSeq - 1).coerceAtLeast(0)
            lastSeq = frame.seq
            lastMicAt = clock()
        }
        audio.feedMic(frame.pcm)
    }

    /** Раз в [TICK_MS]: очки замолчали или не ответили на `voice{on:true}` — возвращаем звук телефону. Открыто для тестов. */
    fun tick() {
        synchronized(this) {
            val t = clock()
            when {
                state == State.ACTIVE && t - lastMicAt > SILENCE_MS -> fallback("silence")
                state == State.ARMED && t - armedAt > READY_MS -> fallback("no_ready")
            }
        }
    }

    private fun arm() {
        synchronized(this) {
            if (state != State.OFF || !enabled()) return
            state = State.ARMED
            armedAt = clock()
            send(HeadsetOut.Voice(true))
            Mb10Log.event(TAG, "headset.voice_armed")
        }
    }

    private fun activate() {
        state = State.ACTIVE
        lastMicAt = clock()
        lastSeq = -1
        outSeq = 0
        lost = 0
        audio.route(true) { pcm -> sendBinary(HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_PLAYBACK, outSeq++, pcm)) }
        Mb10Log.event(TAG, "headset.voice_on")
    }

    /** Выход до конца звонка: маршрут выключен, очкам `voice{on:false}`, в этом звонке голос в очки больше не идёт. */
    private fun fallback(reason: String) {
        if (state == State.ACTIVE) audio.route(false)
        state = State.FALLBACK
        send(HeadsetOut.Voice(false))
        Mb10Log.warnEvent(TAG, "headset.voice_off", "reason" to reason, "lost" to lost)
    }

    private fun release(reason: String) {
        synchronized(this) {
            val was = state
            if (was == State.ACTIVE) audio.route(false)
            if (was == State.ARMED || was == State.ACTIVE) {
                send(HeadsetOut.Voice(false))
                Mb10Log.event(TAG, "headset.voice_off", "reason" to reason, "lost" to lost)
            }
            state = State.OFF
        }
    }

    companion object {
        private const val TAG = "Headset"
        const val TICK_MS = 500L
        /** Очки шлют кадры каждые ≈20 мс; нет их дольше этого — голос возвращается телефону. */
        const val SILENCE_MS = 2_000L
        /** Сколько ждём `voice_ready` после `voice{on:true}`. */
        const val READY_MS = 5_000L
    }
}
