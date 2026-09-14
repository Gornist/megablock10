package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Персонаж (свой или чужой), каким его знает это устройство. publicKeyB64 —
 * первичный идентификатор, как и в остальном протоколе (тот же ключ, что в
 * QR и в подписи транзакций). Часть полей полной модели (cyberware,
 * ramCapacity, accessLevel, daemons, shards) пока не хранится здесь — они
 * появятся вместе с фичами, которые их производят (импланты, кибердека,
 * контейнеры), чтобы не тащить пустые колонки заранее.
 */
@Entity(tableName = "characters")
data class CharacterEntity(
    @PrimaryKey val publicKeyB64: String,
    val callsign: String,
    val faction: String,
    val isNpc: Boolean = false
)
