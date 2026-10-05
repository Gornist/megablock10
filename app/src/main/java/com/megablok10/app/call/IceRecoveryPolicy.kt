package com.megablok10.app.call

/**
 * Что делать со звонком, у которого пропала связь (смена точки доступа, обрыв Wi-Fi). Живая проверка 05.10: после обрыва Wi-Fi на 6 с
 * ICE уходило в DISCONNECTED → FAILED, перезапуска не было, а на экране звонок вечно висел «СОЕДИНЕНИЕ». Теперь:
 *  - [graceMs] ждём, не наладится ли само (DISCONNECTED у WebRTC часто временное);
 *  - если нет — звонящий ([isCaller]) каждые [retryMs] шлёт новый OFFER с перезапуском ICE (кандидаты собираются заново, в том числе на новом
 *    адресе); принимающий только ждёт: перезапуск делает одна сторона, иначе офферы столкнутся;
 *  - если за [giveUpMs] связь не вернулась — [Action.GIVE_UP]: звонок завершается, а не висит.
 * Чистая логика: время передаёт вызывающий, потоки — на нём (вызовы из WebRTC-потока и из корутины), поэтому методы синхронизированы.
 */
class IceRecoveryPolicy(
    private val isCaller: Boolean,
    private val graceMs: Long = GRACE_MS,
    private val retryMs: Long = RETRY_MS,
    private val giveUpMs: Long = GIVE_UP_MS,
) {
    enum class Action { NONE, RESTART, GIVE_UP }

    private var lostSince: Long? = null
    private var lastRestart: Long? = null

    /** Связь есть (CONNECTED/COMPLETED) — отсчёт потери сбрасывается. */
    @Synchronized fun onConnected() {
        lostSince = null
        lastRestart = null
    }

    /** Связь пропала (DISCONNECTED/FAILED). Повторное сообщение о потере отсчёт не сдвигает. */
    @Synchronized fun onLost(now: Long) {
        if (lostSince == null) lostSince = now
    }

    /** Связь потеряна прямо сейчас (для интерфейса: «восстанавливаем»). */
    @Synchronized fun isLost(): Boolean = lostSince != null

    /** Вызывается раз в секунду, пока звонок идёт. */
    @Synchronized fun tick(now: Long): Action {
        val since = lostSince ?: return Action.NONE
        val lost = now - since
        if (lost >= giveUpMs) return Action.GIVE_UP
        if (!isCaller || lost < graceMs) return Action.NONE
        val last = lastRestart
        if (last != null && now - last < retryMs) return Action.NONE
        lastRestart = now
        return Action.RESTART
    }

    companion object {
        const val GRACE_MS = 4_000L
        const val RETRY_MS = 8_000L
        const val GIVE_UP_MS = 45_000L
    }
}
