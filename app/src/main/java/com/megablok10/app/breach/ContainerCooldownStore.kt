package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.DebugConfig
import com.megablok10.app.data.ContainerBreachEntity
import com.megablok10.app.data.Mb10Database

/**
 * Анти-фарм для контейнеров: один и тот же контейнер (свой уникальный id в
 * QR) не должен отдавать лут чаще, чем раз в MockBreach.containerCooldownMinutes
 * на этом устройстве. Отметка пишется только при реальном результате (см.
 * markRewarded — только когда совпал хотя бы один демон), провальная попытка
 * кулдаун не запускает.
 */
object ContainerCooldownStore {
    private val cooldownMs get() = DebugConfig.scaledMs(MockBreach.containerCooldownMinutes * 60_000L)

    /** 0, если контейнер можно вскрывать прямо сейчас; иначе — сколько миллисекунд осталось ждать. */
    suspend fun remainingCooldownMs(context: Context, containerId: String): Long {
        val last = Mb10Database.get(context).containerBreachDao().lastRewardedAt(containerId) ?: return 0
        val elapsed = System.currentTimeMillis() - last
        return (cooldownMs - elapsed).coerceAtLeast(0)
    }

    suspend fun markRewarded(context: Context, containerId: String) {
        Mb10Database.get(context).containerBreachDao().upsert(
            ContainerBreachEntity(containerId = containerId, lastRewardedAt = System.currentTimeMillis())
        )
    }
}
