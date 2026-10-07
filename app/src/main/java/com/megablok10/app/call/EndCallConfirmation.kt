package com.megablok10.app.call

/**
 * Страховка от ложного касания во время разговора: «Завершить» срабатывает со второго нажатия в течение [windowMs] — первое лишь «заряжает» кнопку
 * (она меняет подпись). Одиночное касание щекой или карманом звонок не сбрасывает. Время передаётся снаружи — проверяется без часов.
 */
class EndCallConfirmation(private val windowMs: Long = DEFAULT_WINDOW_MS) {
    private var armedAt: Long = NEVER

    /** true — звонок завершать; false — первое нажатие (или окно истекло), кнопка заряжена заново. */
    fun onTap(now: Long): Boolean {
        if (isArmed(now)) {
            armedAt = NEVER
            return true
        }
        armedAt = now
        return false
    }

    fun isArmed(now: Long): Boolean = armedAt != NEVER && now - armedAt < windowMs

    companion object {
        const val DEFAULT_WINDOW_MS = 3_000L
        private const val NEVER = Long.MIN_VALUE
    }
}
