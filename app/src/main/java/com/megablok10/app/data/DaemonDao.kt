package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface DaemonDao {
    @Query("SELECT * FROM daemons ORDER BY name")
    fun observeAll(): Flow<List<DaemonEntity>>

    @Query("SELECT COUNT(*) FROM daemons")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(daemons: List<DaemonEntity>)

    /** REPLACE — как у шардов: повторное сканирование того же демона обновляет его, если мастер перепечатал QR. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(daemon: DaemonEntity)
}
