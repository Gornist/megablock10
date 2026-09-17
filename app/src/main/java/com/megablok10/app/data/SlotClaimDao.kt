package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface SlotClaimDao {
    /** IGNORE — тот же игрок на тот же слот второй раз ничего не меняет, не переносит claimedAt. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(claim: SlotClaimEntity)

    @Query("SELECT * FROM slot_claims WHERE slotRef = :slotRef ORDER BY claimedAt ASC")
    suspend fun claimsFor(slotRef: String): List<SlotClaimEntity>

    @Query("SELECT COUNT(*) FROM slot_claims WHERE slotRef = :slotRef")
    suspend fun claimCount(slotRef: String): Int

    /** '#', не ':' — см. Container.slotRef. */
    @Query("SELECT * FROM slot_claims WHERE slotRef LIKE :containerId || '#%'")
    fun observeForContainer(containerId: String): Flow<List<SlotClaimEntity>>

    @Query("SELECT EXISTS(SELECT 1 FROM slot_claims WHERE slotRef = :slotRef AND claimantKeyB64 = :claimantKeyB64)")
    suspend fun hasClaimed(slotRef: String, claimantKeyB64: String): Boolean
}
