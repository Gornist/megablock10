package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Шард, отсканированный этим устройством. Все текстовые поля приходят уже
 * готовыми из QR (их пишет мастер игры) — приложение их не генерирует и не
 * интерпретирует, только хранит и показывает.
 *
 * decrypted — устанавливается на устройстве, а не приходит из QR: при
 * первом сохранении шарда (ShardStore.add) равно !decryptAction, дальше
 * меняется на true только после успешного мини-взлома (ShardStore.markDecrypted).
 */
@Entity(tableName = "shards")
data class ShardEntity(
    @PrimaryKey val id: String,
    val badge: String,
    val decryptAction: Boolean,
    val title: String,
    val meta: String,
    val body: String,
    val scannedAt: Long,
    val moneyAmount: Long = 0,
    val decrypted: Boolean = true
)
