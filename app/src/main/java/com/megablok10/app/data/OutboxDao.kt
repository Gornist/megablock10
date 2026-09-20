package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface OutboxDao {
    @Insert
    suspend fun insert(entry: OutboxEntity): Long

    @Query("SELECT * FROM outbox WHERE nextAttemptAt <= :now ORDER BY id ASC")
    suspend fun due(now: Long): List<OutboxEntity>

    @Query("DELETE FROM outbox WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("UPDATE outbox SET attempts = :attempts, nextAttemptAt = :nextAttemptAt WHERE id = :id")
    suspend fun reschedule(id: Long, attempts: Int, nextAttemptAt: Long)

    @Query("DELETE FROM outbox WHERE createdAt < :cutoff")
    suspend fun deleteOlderThan(cutoff: Long): Int

    @Query("SELECT COUNT(*) FROM outbox")
    suspend fun count(): Int
}
