package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ShardDao {
    @Query("SELECT * FROM shards ORDER BY scannedAt DESC")
    fun observeAll(): Flow<List<ShardEntity>>

    /** REPLACE, не IGNORE — повторное сканирование того же шарда обновляет его текст, если мастер перепечатал QR. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(shard: ShardEntity)

    @Query("SELECT * FROM shards WHERE id = :id")
    suspend fun get(id: String): ShardEntity?

    @Query("DELETE FROM shards WHERE id = :id")
    suspend fun delete(id: String)

    @Query("UPDATE shards SET decrypted = 1 WHERE id = :id")
    suspend fun markDecrypted(id: String)
}
