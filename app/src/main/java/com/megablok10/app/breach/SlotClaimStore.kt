package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.SlotClaimEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.presence.PresenceService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Эксклюзивность лута конечного тиража — см. ревизию v9 §6. Заявка на слот
 * подписывается ключом персонажа (тем же, что и денежные транзакции) и
 * рассылается ГОССИПОМ всем сейчас видимым пирам (см. ClaimProtocol —
 * это не полная синхронизация реестров, устройство, которое было офлайн в
 * момент чужого извлечения, не дозаберёт заявку задним числом).
 */
object SlotClaimStore {
    /**
     * Ищет первый (по порядку слотов контейнера) ещё не исчерпанный слот
     * нужного типа, который extractorTier способен извлечь, застолбливает
     * его локально и рассылает заявку. excludeIndices — слоты, уже занятые
     * ДРУГИМИ демонами в этой же попытке (см. DaemonRewards.apply). null —
     * подходящих свободных слотов не осталось ("КЭШ ОЧИЩЕН").
     */
    suspend fun claimNextAvailable(
        context: Context,
        identity: Identity,
        container: Container,
        type: LootType,
        extractorTier: Tier,
        excludeIndices: Set<Int>
    ): Int? {
        val dao = Mb10Database.get(context).slotClaimDao()
        val index = pickSlot(container, type, extractorTier, excludeIndices) { slotRef -> dao.claimCount(slotRef) } ?: return null

        val slotRef = container.slotRef(index)
        val claimedAt = System.currentTimeMillis()
        val signature = IdentityManager.sign(context, ClaimProtocol.signaturePayload(slotRef, identity.publicKeyB64, claimedAt))
        val entity = SlotClaimEntity(slotRef = slotRef, claimantKeyB64 = identity.publicKeyB64, claimedAt = claimedAt, signature = signature)
        dao.insertIfAbsent(entity)
        broadcast(entity)
        return index
    }

    /**
     * Чистый выбор слота без Context/БД — первый по порядку слот нужного
     * типа, который extractorTier способен извлечь и который ещё не
     * исчерпан по тиражу (claimedCount — число уже принятых заявок на него).
     * excludeIndices — слоты, уже занятые ДРУГИМИ демонами в этой же попытке.
     */
    suspend fun pickSlot(
        container: Container,
        type: LootType,
        extractorTier: Tier,
        excludeIndices: Set<Int>,
        claimedCount: suspend (slotRef: String) -> Int
    ): Int? {
        for ((index, slot) in container.loot.withIndex()) {
            if (index in excludeIndices) continue
            if (slot.type != type) continue
            if (!extractorTier.covers(slot.tier)) continue
            val slotRef = container.slotRef(index)
            if (slot.copies > 0 && claimedCount(slotRef) >= slot.copies) continue
            return index
        }
        return null
    }

    /**
     * Все слоты конечного тиража в контейнере уже разобраны — сканировать его
     * дальше некому смысла нет ("КЭШ ОЧИЩЕН", см. CyberdeckScreen). Слоты с
     * copies=0 (бесконечный тираж) никогда не считаются исчерпанными; контейнер
     * совсем без лута (легаси "AP"-QR) исчерпанным тоже не считается — у него
     * просто изначально нечего доставать, это не то же самое, что "уже разобрали".
     */
    suspend fun isExhausted(context: Context, container: Container): Boolean {
        if (container.loot.isEmpty()) return false
        val dao = Mb10Database.get(context).slotClaimDao()
        return container.loot.withIndex().all { (index, slot) ->
            slot.copies > 0 && dao.claimCount(container.slotRef(index)) >= slot.copies
        }
    }

    /** Входящая заявка от другого устройства (см. ChatStore) — принимается только если подпись действительно принадлежит заявленному ключу. */
    suspend fun receive(context: Context, claim: SlotClaimEntity) {
        val payload = ClaimProtocol.signaturePayload(claim.slotRef, claim.claimantKeyB64, claim.claimedAt)
        if (!IdentityManager.verify(claim.claimantKeyB64, payload, claim.signature)) return
        Mb10Database.get(context).slotClaimDao().insertIfAbsent(claim)
    }

    private suspend fun broadcast(claim: SlotClaimEntity) {
        withContext(Dispatchers.IO) {
            PresenceService.peers.value.forEach { peer -> ClaimClient.send(peer.host, peer.port, claim) }
        }
    }
}
