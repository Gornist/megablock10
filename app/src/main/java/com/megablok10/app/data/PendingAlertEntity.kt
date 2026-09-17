package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Сигнал СБ, который ещё не удалось доставить ни одному онлайн-игроку
 * фракции-владельца — стоит в очереди на устройстве взломщика (см.
 * SecAlertStore) до sendAt (задержка тира, растянутая нейтрализаторами),
 * дальше пытается уйти при каждом изменении списка пиров, пока не истечёт
 * ttl — тогда просто удаляется, без сообщения "протухло".
 */
@Entity(tableName = "pending_alerts")
data class PendingAlertEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val containerId: String,
    val containerName: String,
    val faction: String,
    val payload: String,
    val sendAt: Long,
    val ttl: Long
)
