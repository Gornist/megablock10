package com.megablok10.app.breach

import com.megablok10.app.data.SlotClaimEntity

/**
 * Построчный протокол поверх того же TCP-сокета, что чат и звонки (см.
 * ChatServer — один accept-луп различает протоколы по магическому префиксу
 * первой строки). Разносит по сети заявки на слот лута конечного тиража,
 * чтобы устройства разных игроков видели чужие успешные извлечения и не
 * считали один и тот же слот свободным одновременно.
 *
 * Это ГОССИП, не полная синхронизация: заявка рассылается один раз, в
 * момент создания, всем СЕЙЧАС видимым пирам (см. SlotClaimStore.claim).
 * Устройство, которое было офлайн в момент чьего-то извлечения, не
 * дозаберёт эту заявку задним числом — узнает о ней только из следующей
 * заявки на тот же slotRef, если попытается его тоже застолбить. Для
 * масштаба и продолжительности одного LARP-акта это осознанный компромисс
 * (см. ревизию v9 §6), а не забытый TODO.
 */
object ClaimProtocol {
    private const val MAGIC = "MB10CLAIM"

    fun encode(claim: SlotClaimEntity): String =
        listOf(MAGIC, "v1", claim.slotRef, claim.claimantKeyB64, claim.claimedAt.toString(), claim.signature).joinToString(":")

    fun decode(raw: String): SlotClaimEntity? {
        val parts = raw.split(":")
        if (parts.size < 6 || parts[0] != MAGIC) return null
        return try {
            SlotClaimEntity(
                slotRef = parts[2],
                claimantKeyB64 = parts[3],
                claimedAt = parts[4].toLongOrNull() ?: return null,
                signature = parts[5]
            )
        } catch (e: Exception) {
            null
        }
    }

    /** Байты, которые подписывает заявитель — тот же ключ, что подписывает денежные транзакции. */
    fun signaturePayload(slotRef: String, claimantKeyB64: String, claimedAt: Long): ByteArray =
        "$slotRef|$claimantKeyB64|$claimedAt".toByteArray(Charsets.UTF_8)
}
