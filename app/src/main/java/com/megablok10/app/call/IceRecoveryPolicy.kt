package com.megablok10.app.call

/**
 * Что делать со звонком, у которого пропала связь (смена точки доступа, обрыв Wi-Fi). Живая проверка 05.10: после обрыва Wi-Fi на 6 с
 * ICE уходило в DISCONNECTED → FAILED, перезапуска не было, а на экране звонок вечно висел «СОЕДИНЕНИЕ». Теперь:
 *  - [graceMs] ждём, не наладится ли само (DISCONNECTED у WebRTC часто временное);
 *  - если нет — звонящий ([isCaller]) шлёт новый OFFER с перезапуском ICE и повторяет его каждые [retryMs], **пока собеседник не ответил**
 *    ([onRestartAnswered]): первый OFFER может уйти, когда сети ещё нет (повторная проверка того же дня: Wi-Fi вернулся через секунду после
 *    отправки, звонящий сам стал CONNECTED, а собеседник так и не получил OFFER — без повторов он зависал). Принимающий только ждёт: перезапуск
 *    делает одна сторона, иначе офферы столкнутся;
 *  - если за [giveUpMs] связь не вернулась (или перезапуск так и не подтвердили) — [Action.GIVE_UP]: звонок завершается, а не висит.
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
    private var restartPendingSince: Long? = null
    private var lastRestart: Long? = null

    /** Связь есть (CONNECTED/COMPLETED). Неподтверждённый перезапуск это не отменяет: у собеседника связь могла не вернуться. */
    @Synchronized fun onConnected() {
        lostSince = null
        if (restartPendingSince == null) lastRestart = null
    }

    /** Связь пропала (DISCONNECTED/FAILED). Повторное сообщение о потере отсчёт не сдвигает. */
    @Synchronized fun onLost(now: Long) {
        if (lostSince == null) lostSince = now
    }

    /** Собеседник ответил на наш OFFER перезапуска — повторять его больше не нужно. */
    @Synchronized fun onRestartAnswered() {
        restartPendingSince = null
        lastRestart = null
    }

    /** Связь потеряна прямо сейчас (для интерфейса: «восстанавливаем»). */
    @Synchronized fun isLost(): Boolean = lostSince != null

    /** Вызывается раз в секунду, пока звонок идёт. */
    @Synchronized fun tick(now: Long): Action {
        val since = listOfNotNull(lostSince, restartPendingSince).minOrNull()
        return when {
            since == null -> Action.NONE
            now - since >= giveUpMs -> Action.GIVE_UP
            isCaller && restartDue(now) -> {
                lastRestart = now
                if (restartPendingSince == null) restartPendingSince = now
                Action.RESTART
            }
            else -> Action.NONE
        }
    }

    /** Пора слать (повторять) OFFER перезапуска: связь потеряна дольше [graceMs] или прошлый ещё без ответа — и с прошлой отправки прошло не меньше [retryMs]. */
    private fun restartDue(now: Long): Boolean {
        val lost = lostSince
        val needed = restartPendingSince != null || (lost != null && now - lost >= graceMs)
        val last = lastRestart
        return needed && (last == null || now - last >= retryMs)
    }

    companion object {
        const val GRACE_MS = 4_000L
        const val RETRY_MS = 8_000L
        const val GIVE_UP_MS = 45_000L
    }
}
