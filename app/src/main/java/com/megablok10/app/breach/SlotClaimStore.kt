package com.megablok10.app.breach

import com.megablok10.app.collector.CollectorClient
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.data.SlotClaimDao
import com.megablok10.app.data.SlotClaimEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.mesh.addressesOf
import com.megablok10.kit.mesh.sendToFirstReachable
import com.megablok10.kit.net.LineSocketClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Эксклюзивность лута конечного тиража — см. ревизию v9 §6 и §5 мастерского
 * ТЗ (упрощённая версия). Если в Настройках задан адрес мастерского
 * коллектора, слоты конечного тиража арбитрирует ОН — см.
 * [claimViaCollector]: коллектор недоступен или слот исчерпан → лут просто
 * не выдаётся, без очереди "ожидает подтверждения". Локальный ГОССИП
 * (ClaimProtocol, рассылка всем видимым пирам) остаётся резервным путём на
 * случай, когда коллектор не настроен вовсе (тестирование без дашборда) —
 * тогда, как и раньше, гонка между устройствами не исключена в принципе,
 * это осознанный компромисс на случай отсутствия мастерского ноутбука.
 */
class SlotClaimStore(
    private val dao: SlotClaimDao,
    private val identityStore: IdentityStore,
    private val settings: CollectorSettings,
    private val collector: CollectorClient,
    private val peers: () -> List<PeerInfo>,
    private val lines: LineSocketClient,
) {
    /**
     * Ищет первый (по порядку слотов контейнера) ещё не исчерпанный слот
     * нужного типа, который extractorTier способен извлечь, застолбливает
     * его локально и рассылает заявку. excludeIndices — слоты, уже занятые
     * ДРУГИМИ демонами в этой же попытке (см. DaemonRewards.apply). null —
     * подходящих свободных слотов не осталось ("КЭШ ОЧИЩЕН").
     */
    suspend fun claimNextAvailable(
        identity: Identity,
        container: Container,
        type: LootType,
        extractorTier: Tier,
        excludeIndices: Set<Int>
    ): Int? {
        // Слот, в котором коллектор отказал (глобально исчерпан, а локальный счётчик ещё не в курсе),
        // не должен обрывать извлечение целиком — пробуем следующий подходящий слот того же типа.
        val refused = mutableSetOf<Int>()
        while (true) {
            val index = pickSlot(container, type, extractorTier, excludeIndices + refused) { slotRef -> dao.claimCount(slotRef) } ?: return null

            val slotRef = container.slotRef(index)
            val claimedAt = System.currentTimeMillis()
            val signature = identityStore.sign(ClaimProtocol.signaturePayload(slotRef, identity.publicKeyB64, claimedAt))

            val collectorUrl = settings.baseUrl()
            if (collectorUrl != null && container.loot[index].copies > 0) {
                val granted = collector.claimSlot(collectorUrl, slotRef, identity.publicKeyB64, claimedAt, signature, settings.gameSecret())
                if (!granted) {
                    Mb10Log.warnEvent("Slots", "slot.refused_by_server", "slot" to slotRef)
                    refused += index
                    continue
                }
            }

            val entity = SlotClaimEntity(slotRef = slotRef, claimantKeyB64 = identity.publicKeyB64, claimedAt = claimedAt, signature = signature)
            dao.insertIfAbsent(entity)
            Mb10Log.event("Slots", "slot.claimed", "slot" to slotRef, "viaServer" to (collectorUrl != null && container.loot[index].copies > 0))
            broadcast(entity)
            return index
        }
    }

    /**
     * Все слоты конечного тиража в контейнере уже разобраны — сканировать его
     * дальше некому смысла нет ("КЭШ ОЧИЩЕН", см. CyberdeckScreen). Слоты с
     * copies=0 (бесконечный тираж) никогда не считаются исчерпанными; контейнер
     * совсем без лута (легаси "AP"-QR) исчерпанным тоже не считается — у него
     * просто изначально нечего доставать, это не то же самое, что "уже разобрали".
     */
    suspend fun isExhausted(container: Container): Boolean {
        if (container.loot.isEmpty()) return false
        return container.loot.withIndex().all { (index, slot) ->
            slot.copies > 0 && dao.claimCount(container.slotRef(index)) >= slot.copies
        }
    }

    /** Входящая заявка от другого устройства (см. ChatStore) — принимается только если подпись действительно принадлежит заявленному ключу. */
    suspend fun receive(claim: SlotClaimEntity) {
        val payload = ClaimProtocol.signaturePayload(claim.slotRef, claim.claimantKeyB64, claim.claimedAt)
        if (!Ecdsa.verify(claim.claimantKeyB64, payload, claim.signature)) {
            Mb10Log.warnEvent("Slots", "slot.claim_in_bad_signature", "slot" to claim.slotRef, "from" to Mb10Log.short(claim.claimantKeyB64))
            return
        }
        dao.insertIfAbsent(claim)
        Mb10Log.event("Slots", "slot.claim_in", "slot" to claim.slotRef, "from" to Mb10Log.short(claim.claimantKeyB64))
    }

    private suspend fun broadcast(claim: SlotClaimEntity) {
        withContext(Dispatchers.IO) {
            val line = ClaimProtocol.encode(claim)
            // По разу на игрока (у него бывает несколько адресов — kit PeerTable): заявка идемпотентна, но лишние соединения ни к чему.
            val known = peers()
            known.map { it.pubKeyB64 }.distinct().forEach { key ->
                sendToFirstReachable(known.addressesOf(key)) { lines.sendLineOutcome(it.host, it.port, line) }
            }
        }
    }

    companion object {
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
                val fits = index !in excludeIndices && slot.type == type && extractorTier.covers(slot.tier)
                // Тираж спрашиваем, только если слот вообще подходит и конечен (0 — бесконечный): claimedCount ходит в базу.
                if (fits && (slot.copies <= 0 || claimedCount(container.slotRef(index)) < slot.copies)) return index
            }
            return null
        }
    }
}
