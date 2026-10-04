package com.megablok10.rules

/**
 * Числа взлома, не привязанные к тиру: остывание узла, прибавка JITTER, цель и буфер шифр-замка.
 * Копия значений лежит в netrun/data/rules/breach.json — тест BreachJsonTest сверяет файл с этими константами.
 */
object BreachConstants {
    /** Анти-фарм: один и тот же контейнер не платит лут чаще этого интервала (ContainerCooldownStore в приложении). */
    const val CONTAINER_COOLDOWN_MINUTES = 30

    /** Демон JITTER, выбранный в деку взлома, прибавляет столько секунд к таймеру попытки. */
    const val JITTER_BONUS_SEC = 15

    /** Последние секунды до итога, когда шапка таймера мигает и звучит реплика LOW_TIME. */
    const val LOW_TIME_SEC = 10

    /** Последние секунды, на каждом тике которых звучит предупреждение. */
    const val WARNING_SEC = 5

    /** Реплики HALF_TIME/LOW_TIME — только если таймер попытки длиннее этого (иначе они совпали бы с началом). */
    const val TIME_EVENTS_MIN_TIMER_SEC = 20

    /** Длина цели расшифровки шарда — по тиру шарда (1/2/3), индекс = tier-1. */
    val SHARD_DECRYPT_TARGET_LENGTH = listOf(3, 4, 5)

    /** Буфер шифр-замка = длина цели + столько клеток запаса. */
    const val DECRYPT_BUFFER_EXTRA = 2

    /** Длина цели расшифровки шарда тира [shardTier]; неизвестный тир — 3, как раньше. */
    fun shardDecryptTargetLength(shardTier: Int): Int = SHARD_DECRYPT_TARGET_LENGTH.getOrElse(shardTier - 1) { 3 }
}
