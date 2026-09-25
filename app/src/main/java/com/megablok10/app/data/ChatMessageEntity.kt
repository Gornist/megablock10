package com.megablok10.app.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Одно сообщение — своё или чужое, фракционное или личное. Своих и чужих не
 * различаем отдельным полем: строка с fromPubKeyB64 == моему ключу и есть
 * "своя". Дедупликация не нужна: транспорт — один TCP-коннект на сообщение
 * до конкретного адресата, повторной доставки той же записи не бывает.
 *
 * [status] — только у своих личных сообщений ([MessageStatus]): ушло ли и дошло ли до адресата. Растёт и не убывает.
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
    val timestamp: Long,
    @ColumnInfo(defaultValue = "0") val status: Int = MessageStatus.NONE,
)

/**
 * Статус своего личного сообщения (docs/refactor-plan.md, D3). Порядок значений — порядок жизни сообщения: статус меняется только
 * вверх (запрос с `status < :new`), поэтому поздний ответ очереди не откатит «прочитано» обратно в «доставлено».
 */
object MessageStatus {
    /** Входящее, фракционное или записанное до статусов. */
    const val NONE = 0
    /** Не ушло: адресата не видно или не достучались (лежит в очереди исходящих, если его можно туда ставить). */
    const val PENDING = 1
    /** Ушло, но ответа получателя нет (старая версия у него или обрыв) — могло дойти. */
    const val SENT = 2
    /** Получатель подтвердил, что сохранил (ответ `ok`, D2). */
    const val DELIVERED = 3
    /** Получатель открыл тред (отчёт о прочтении, D4). */
    const val READ = 4
}
