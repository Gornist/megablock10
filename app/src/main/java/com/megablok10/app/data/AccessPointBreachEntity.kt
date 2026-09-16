package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Отметка "эту точку доступа только что успешно вскрыли на этом устройстве".
 * Существует только для анти-фарма: одна и та же точка не должна отдавать
 * награду демонов чаще, чем раз в MockBreach.accessPointCooldownMinutes —
 * иначе точку можно пересдавать бесконечно ради денег/шардов. Пишется
 * только при реальной награде (совпал хотя бы один демон), не на каждую
 * попытку — провал не должен блокировать повторный заход.
 */
@Entity(tableName = "access_point_breaches")
data class AccessPointBreachEntity(
    @PrimaryKey val accessPointId: String,
    val lastRewardedAt: Long
)
