package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface ContainerBreachDao {
    @Query("SELECT lastRewardedAt FROM container_breaches WHERE containerId = :containerId")
    suspend fun lastRewardedAt(containerId: String): Long?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: ContainerBreachEntity)

    @Query("DELETE FROM container_breaches")
    suspend fun deleteAll()
}
