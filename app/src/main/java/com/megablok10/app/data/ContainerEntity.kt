package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Локальная копия контейнера, который это устройство САМО выпустило в
 * Мастерской — не то, что игроки сканируют (для них контейнер целиком живёт
 * в QR, транзитно). Существует только чтобы у мастера был дашборд "что я
 * напечатал" и можно было свериться с SlotClaimEntity по тиражу, не
 * перевводя состав лута заново. lootJson — та же '; ,'-схема, что в
 * Mb10QrCodec.encodeContainer, не настоящий JSON (в проекте нет JSON-библиотеки).
 */
@Entity(tableName = "containers")
data class ContainerEntity(
    @PrimaryKey val id: String,
    val name: String,
    val tier: Int,
    val ownerFaction: String,
    val lootJson: String
)
