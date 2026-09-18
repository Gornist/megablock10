package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface PendingChangeRecordDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(record: PendingChangeRecordEntity)

    @Query("SELECT * FROM pending_change_records ORDER BY seq ASC LIMIT :limit")
    suspend fun nextBatch(limit: Int): List<PendingChangeRecordEntity>

    @Query("DELETE FROM pending_change_records WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<String>)

    @Query("SELECT COUNT(*) FROM pending_change_records")
    suspend fun count(): Int
}
