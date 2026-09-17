package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Одноразовый токен уже применён на этом устройстве — сейчас только RAM-апгрейд, но ключ по токену, а не по смыслу, так что подходит для любого будущего одноразового QR. */
@Entity(tableName = "consumed_tokens")
data class ConsumedTokenEntity(
    @PrimaryKey val token: String,
    val consumedAt: Long
)
