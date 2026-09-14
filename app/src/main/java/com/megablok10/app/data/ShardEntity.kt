package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Шард, отсканированный этим устройством. Все текстовые поля приходят уже
 * готовыми из QR (их пишет мастер игры) — приложение их не генерирует и не
 * интерпретирует, только хранит и показывает.
 */
@Entity(tableName = "shards")
data class ShardEntity(
    @PrimaryKey val id: String,
    val badge: String,
    val decryptAction: Boolean,
    val title: String,
    val meta: String,
    val body: String,
    val scannedAt: Long
)
