package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface CallLogDao {
    @Insert
    suspend fun insert(entry: CallLogEntity): Long

    @Query("SELECT * FROM call_log ORDER BY startedAt DESC")
    fun observeAll(): Flow<List<CallLogEntity>>
}
