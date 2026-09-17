package com.megablok10.app.data

import androidx.room.Entity

/**
 * Одна заявка на слот лута конечного тиража — слот "containerId#index"
 * достаётся первым `copies` заявкам по claimedAt (см. SlotClaimStore).
 * Составной ключ (slotRef, claimantKeyB64): один и тот же игрок не может
 * застолбить один слот дважды, но разные игроки на один slotRef — заявки
 * рассылаются широковещательно и хранятся у всех, кто их получил.
 * signature — подпись claimantKeyB64 поверх slotRef+claimedAt тем же ключом,
 * что и денежные транзакции; без неё нельзя было бы отличить чужую честную
 * заявку от фальшивой, разосланной, чтобы вручную "погасить" чей-то тираж.
 */
@Entity(tableName = "slot_claims", primaryKeys = ["slotRef", "claimantKeyB64"])
data class SlotClaimEntity(
    val slotRef: String,
    val claimantKeyB64: String,
    val claimedAt: Long,
    val signature: String
)
