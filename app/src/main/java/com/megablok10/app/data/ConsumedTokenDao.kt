package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface ConsumedTokenDao {
    /** IGNORE и возвращаем rowid — вызывающая сторона по -1 понимает "токен уже был применён, не занося дважды". */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(token: ConsumedTokenEntity): Long

    @Query("SELECT EXISTS(SELECT 1 FROM consumed_tokens WHERE token = :token)")
    suspend fun isConsumed(token: String): Boolean
}
