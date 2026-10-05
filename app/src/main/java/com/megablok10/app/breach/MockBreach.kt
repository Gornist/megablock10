package com.megablok10.app.breach

import com.megablok10.rules.BreachConstants

/**
 * Стартовый набор демона персонажа и глобальные (не завязанные на тир
 * контейнера) параметры баланса. gridSize/timerSec/deadCells/corruptedCodes
 * теперь приходят из BreachTierParams.forTier(container.tier) — здесь их
 * больше нет, единственная зависящая от игрока величина (буфер) — это
 * Identity.ramCapacity, не константа. Сами числа — в :rules ([BreachConstants]).
 */
object MockBreach {
    /** Анти-фарм: один и тот же контейнер не платит лут чаще этого интервала (см. ContainerCooldownStore). */
    const val containerCooldownMinutes = BreachConstants.CONTAINER_COOLDOWN_MINUTES

    /** Длина цели расшифровки шарда — по тиру шарда (1/2/3), индекс = tier-1. */
    val shardDecryptTargetLength = BreachConstants.SHARD_DECRYPT_TARGET_LENGTH

    val daemons = listOf(
        Daemon("datamine_v1", "Datamine V1", listOf("1C", "55"), tier = Tier.BASE, effect = DaemonEffect.EXTRACT_SHARD)
    )
}
