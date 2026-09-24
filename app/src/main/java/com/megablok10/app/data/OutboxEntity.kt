package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** Неотправленное сообщение чата: строка протокола целиком, адресат и график повторов (см. chat/OutboxStore). */
// OutboxDao.due() фильтрует по nextAttemptAt <= :now на каждом тике очереди — без индекса это полный скан таблицы.
@Entity(tableName = "outbox", indices = [Index("nextAttemptAt")])
data class OutboxEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val toPubKeyB64: String,
    val wireLine: String,
    val createdAt: Long,
    val attempts: Int = 0,
    val nextAttemptAt: Long = 0
)
