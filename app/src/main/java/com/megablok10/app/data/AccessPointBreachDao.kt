package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface AccessPointBreachDao {
    @Query("SELECT lastRewardedAt FROM access_point_breaches WHERE accessPointId = :accessPointId")
    suspend fun lastRewardedAt(accessPointId: String): Long?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: AccessPointBreachEntity)
}
