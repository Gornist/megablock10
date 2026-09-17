package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Шард, отсканированный этим устройством. Все текстовые поля приходят уже
 * готовыми из QR (их пишет мастер игры, либо они приходят внутри лута
 * контейнера) — приложение их не генерирует и не интерпретирует, только
 * хранит и показывает.
 *
 * decrypted — устанавливается на устройстве, а не приходит из QR: при
 * первом сохранении шарда (ShardStore.add) равно !decryptAction, дальше
 * меняется на true только после успешного мини-взлома (ShardStore.markDecrypted).
 *
 * tier/valueHint — ревизия v9: tier определяет длину цели расшифровки (3/4/5
 * символов), valueHint — текст мастера для отыгрыша торга, приложение цену
 * не считает. Поле badge убрано — ярлык в списке вычисляется из
 * decryptAction+tier+decrypted при отображении (см. ShardsScreen.resolveBadge),
 * не хранится отдельно и не может противоречить самому себе.
 */
@Entity(tableName = "shards")
data class ShardEntity(
    @PrimaryKey val id: String,
    val decryptAction: Boolean,
    val tier: Int,
    val valueHint: String,
    val title: String,
    val meta: String,
    val body: String,
    val scannedAt: Long,
    val moneyAmount: Long = 0,
    val decrypted: Boolean = true
)
