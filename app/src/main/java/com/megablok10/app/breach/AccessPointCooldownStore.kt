package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.data.AccessPointBreachEntity
import com.megablok10.app.data.Mb10Database

/**
 * Анти-фарм для точек доступа: одна и та же точка (свой уникальный id в QR)
 * не должна отдавать награду демонов чаще, чем раз в
 * MockBreach.accessPointCooldownMinutes на этом устройстве. Отметка пишется
 * только при реальной награде (см. markRewarded — вызывается из
 * BreachAccessPointFlow только когда совпал хотя бы один демон), провальная
 * попытка кулдаун не запускает — повторный заход после неудачи не нужно
 * ничем ограничивать сверх уже существующего "точка заблокирована до конца
 * акта" в тексте результата.
 */
object AccessPointCooldownStore {
    private val cooldownMs = MockBreach.accessPointCooldownMinutes * 60_000L

    /** 0, если точку можно вскрывать прямо сейчас; иначе — сколько миллисекунд осталось ждать. */
    suspend fun remainingCooldownMs(context: Context, accessPointId: String): Long {
        val last = Mb10Database.get(context).accessPointBreachDao().lastRewardedAt(accessPointId) ?: return 0
        val elapsed = System.currentTimeMillis() - last
        return (cooldownMs - elapsed).coerceAtLeast(0)
    }

    suspend fun markRewarded(context: Context, accessPointId: String) {
        Mb10Database.get(context).accessPointBreachDao().upsert(
            AccessPointBreachEntity(accessPointId = accessPointId, lastRewardedAt = System.currentTimeMillis())
        )
    }
}
