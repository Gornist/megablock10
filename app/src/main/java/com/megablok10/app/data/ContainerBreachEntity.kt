package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Отметка "этот контейнер только что успешно вскрыли на этом устройстве".
 * Существует только для анти-фарма: один и тот же контейнер не должен
 * отдавать лут чаще, чем раз в MockBreach.containerCooldownMinutes — иначе
 * его можно пересдавать бесконечно ради денег/шардов/демонов. Пишется
 * только при реальном результате (совпал хотя бы один демон), не на каждую
 * попытку — провал не должен блокировать повторный заход.
 */
@Entity(tableName = "container_breaches")
data class ContainerBreachEntity(
    @PrimaryKey val containerId: String,
    val lastRewardedAt: Long
)
