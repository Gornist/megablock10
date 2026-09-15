package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Одно сообщение — своё или чужое, фракционное или личное. Своих и чужих не
 * различаем отдельным полем: строка с fromPubKeyB64 == моему ключу и есть
 * "своя". Дедупликация не нужна: транспорт — один TCP-коннект на сообщение
 * до конкретного адресата, повторной доставки той же записи не бывает.
 */
@Entity(tableName = "chat_messages")
data class ChatMessageEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val type: String,
    val fromPubKeyB64: String,
    val fromCallsign: String,
    val faction: String,
    val toPubKeyB64: String,
    val body: String,
    val timestamp: Long
)
