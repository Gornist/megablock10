package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ContainerDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(container: ContainerEntity)

    @Query("SELECT * FROM containers ORDER BY id")
    fun observeAll(): Flow<List<ContainerEntity>>
}
