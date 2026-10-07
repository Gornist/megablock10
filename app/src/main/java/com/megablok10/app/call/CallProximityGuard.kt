package com.megablok10.app.call

import android.content.Context
import android.os.PowerManager
import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private const val TAG = "CallProximity"

/** Датчик приближения гасит экран, пока телефон у уха: исходящий вызов и разговор (входящий звонок игрок ещё должен видеть и нажать «Принять»). */
internal fun wantsScreenOff(phase: CallPhase): Boolean = phase == CallPhase.OUTGOING_RINGING || phase == CallPhase.IN_CALL

/** Блокировка «экран гаснет у лица» — обёртка над [PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK], отделена, чтобы логика проверялась без Android. */
interface ProximityScreenLock {
    val supported: Boolean
    fun acquire()
    fun release()
}

/**
 * Экран приложения во время разговора оставался включённым, и щека у уха нажимала «Завершить» (живая проверка 07.10, дважды сбросил звонок). Пока звонок
 * идёт ([wantsScreenOff]), держим proximity-блокировку: телефон у лица — экран гаснет и не принимает касаний, убрал — зажигается. Звук разговора идёт в
 * ушной динамик (переключателя громкой связи в приложении нет), так что «у уха» — обычное положение.
 */
class CallProximityGuard(private val calls: CallControls, private val lock: ProximityScreenLock) {
    fun start(scope: CoroutineScope) {
        if (!lock.supported) {
            Mb10Log.event(TAG, "call.proximity", "state" to "unsupported")
            return
        }
        scope.launch {
            try {
                calls.state.map { wantsScreenOff(it.phase) }.distinctUntilChanged().collect { on ->
                    if (on) lock.acquire() else lock.release()
                    Mb10Log.event(TAG, "call.proximity", "state" to if (on) "on" else "off")
                }
            } finally {
                lock.release() // сессия остановлена посреди звонка (сброс персонажа) — блокировка не должна остаться
            }
        }
    }
}

/** Настоящая блокировка. Снятие ждёт, пока лицо отодвинется: иначе экран вспыхнет у самого уха и снова поймает касание. */
class AndroidProximityScreenLock(context: Context) : ProximityScreenLock {
    private val lock: PowerManager.WakeLock?
    override val supported: Boolean

    init {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        supported = pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)
        lock = if (supported) pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "mb10:call-proximity").apply { setReferenceCounted(false) } else null
    }

    @Suppress("WakelockTimeout") // снимается по концу звонка; страховка — таймаут 3 ч ниже
    override fun acquire() { lock?.acquire(MAX_HOLD_MS) }

    override fun release() {
        val l = lock ?: return
        if (l.isHeld) l.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
    }

    private companion object {
        const val MAX_HOLD_MS = 3 * 60 * 60 * 1000L
    }
}
