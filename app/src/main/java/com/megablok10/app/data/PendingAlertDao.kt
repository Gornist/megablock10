package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query

@Dao
interface PendingAlertDao {
    @Insert
    suspend fun insert(alert: PendingAlertEntity): Long

    @Query("SELECT * FROM pending_alerts")
    suspend fun all(): List<PendingAlertEntity>

    @Delete
    suspend fun delete(alert: PendingAlertEntity)

    @Query("DELETE FROM pending_alerts WHERE ttl < :now")
    suspend fun deleteExpired(now: Long)
}
