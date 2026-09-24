package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface SlotClaimDao {
    /** IGNORE — тот же игрок на тот же слот второй раз ничего не меняет, не переносит claimedAt. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(claim: SlotClaimEntity)

    @Query("SELECT COUNT(*) FROM slot_claims WHERE slotRef = :slotRef")
    suspend fun claimCount(slotRef: String): Int
}
