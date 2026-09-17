package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy

@Dao
interface ConsumedTokenDao {
    /** IGNORE и возвращаем rowid — вызывающая сторона по -1 понимает "токен уже был применён, не занося дважды". */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(token: ConsumedTokenEntity): Long
}
