package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface SequenceDao {
    @Query("SELECT value FROM sequences WHERE name = :name")
    suspend fun get(name: String): Long?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(sequence: SequenceEntity)
}
