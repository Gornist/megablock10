package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * Журнал записей, которые сервер уже подтвердил: из очереди (pending_change_records) они уходят сюда и хранятся
 * [ACCEPTED_RETENTION_MS]. Если сервер восстановят из резервной копии, сделанной раньше подтверждения, он сообщит меньший
 * последний seq (knownSeq), и записи сверх него вернутся в очередь (RoomChangeQueue.requeueAcceptedAbove) — иначе подтверждённые,
 * но потерянные сервером записи не осталось бы нигде.
 */
@Entity(tableName = "accepted_change_records", primaryKeys = ["id"], indices = [Index("acceptedAt")])
data class AcceptedChangeRecordEntity(
    val id: String,
    val subjectKeyB64: String,
    val seq: Long,
    val happenedAt: Long,
    val field: String,
    val oldValue: String?,
    val newValue: String?,
    val reason: String,
    val sourceRef: String?,
    val actor: String,
    val signature: String,
    val acceptedAt: Long,
)

/** Сколько хранить подтверждённые записи: с большим запасом больше интервала резервных копий сервера (30 мин). */
const val ACCEPTED_RETENTION_MS = 6 * 60 * 60 * 1000L

@Dao
interface AcceptedChangeRecordDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(records: List<AcceptedChangeRecordEntity>)

    @Query("SELECT * FROM accepted_change_records WHERE subjectKeyB64 = :subject AND seq > :seq ORDER BY seq ASC")
    suspend fun above(subject: String, seq: Long): List<AcceptedChangeRecordEntity>

    @Query("DELETE FROM accepted_change_records WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<String>)

    @Query("DELETE FROM accepted_change_records WHERE acceptedAt < :before")
    suspend fun deleteAcceptedBefore(before: Long)

    @Query("SELECT MAX(seq) FROM accepted_change_records")
    suspend fun maxSeq(): Long?
}
