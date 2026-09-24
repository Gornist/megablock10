package com.megablok10.app.breach

import com.megablok10.app.DebugConfig
import com.megablok10.app.data.ContainerBreachDao
import com.megablok10.app.data.ContainerBreachEntity

/**
 * Анти-фарм для контейнеров: один и тот же контейнер (свой уникальный id в
 * QR) не должен отдавать лут чаще, чем раз в MockBreach.containerCooldownMinutes
 * на этом устройстве. Отметка пишется только при реальном результате (см.
 * markRewarded — только когда совпал хотя бы один демон), провальная попытка
 * кулдаун не запускает.
 */
class ContainerCooldownStore(private val dao: ContainerBreachDao) {
    private val cooldownMs get() = DebugConfig.scaledMs(MockBreach.containerCooldownMinutes * 60_000L)

    /** 0, если контейнер можно вскрывать прямо сейчас; иначе — сколько миллисекунд осталось ждать. */
    suspend fun remainingCooldownMs(containerId: String): Long {
        val last = dao.lastRewardedAt(containerId) ?: return 0
        val elapsed = System.currentTimeMillis() - last
        return (cooldownMs - elapsed).coerceAtLeast(0)
    }

    suspend fun markRewarded(containerId: String) {
        dao.upsert(ContainerBreachEntity(containerId = containerId, lastRewardedAt = System.currentTimeMillis()))
    }

    /** Все отметки — прочь (отладочная команда стенда e2e `cooldowns reset`). */
    suspend fun resetAll() = dao.deleteAll()
}
