package com.megablok10.app.breach

import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.wallet.TransactionStore

/** Что реально случилось после резолва попытки — для текста на экране результата. */
data class RewardOutcome(
    val eddies: Long,
    val extractedShardTitles: List<String>,
    val extractedDaemonNames: List<String>,
    val cacheExhausted: Boolean,
    val matchedEffects: Set<DaemonEffect>
)

/**
 * Применяет результат совпавших демонов после резолва попытки — ревизия v9:
 * лут теперь на контейнере, не на демоне (демон лишь определяет, ЧТО можно
 * извлечь — EXTRACT_SHARD/EXTRACT_DAEMON — а не САМ являться призом). Эдди
 * начисляются автоматически при любом не-FAIL исходе, независимо от того,
 * какие именно демоны выбраны (см. ContainerEddies). На FAIL — только
 * matchedEffects (пустой набор) для SecAlertStore, ни денег, ни лута.
 */
class DaemonRewards(
    private val wallet: TransactionStore,
    private val shards: ShardStore,
    private val daemons: DaemonStore,
    private val slotClaims: SlotClaimStore,
    private val settings: CollectorSettings,
) {
    suspend fun apply(identity: Identity, container: Container, result: BreachResult, attemptId: String): RewardOutcome {
        val matched = result.allDaemons.filter { it.id in result.matchedIds }
        val matchedEffects = matched.map { it.effect }.toSet()

        if (result.outcome == BreachOutcome.FAIL) {
            return RewardOutcome(0, emptyList(), emptyList(), cacheExhausted = false, matchedEffects = matchedEffects)
        }

        val eddies = ContainerEddies.roll(container.tier) +
            if (DaemonEffect.MINER in matchedEffects) ContainerEddies.minerBonus(container.tier) else 0L
        wallet.creditContainerEddies(attemptId, eddies, container.name)

        val lootKey = LootCrypto.deriveKey(settings.gameSecret())
        val claimedThisAttempt = mutableSetOf<Int>()
        val shardTitles = mutableListOf<String>()
        val daemonNames = mutableListOf<String>()
        var exhausted = false

        matched.forEach { daemon ->
            val lootType = when (daemon.effect) {
                DaemonEffect.EXTRACT_SHARD -> LootType.SHARD
                DaemonEffect.EXTRACT_DAEMON -> LootType.DAEMON
                else -> return@forEach
            }
            val slotIndex = slotClaims.claimNextAvailable(identity, container, lootType, daemon.tier, claimedThisAttempt)
            if (slotIndex == null) {
                exhausted = true
                return@forEach
            }
            claimedThisAttempt += slotIndex
            val slot = container.loot[slotIndex]
            val slotRef = container.slotRef(slotIndex)
            when (val loot = LootCrypto.decrypt(slot.payload, lootKey)?.let(LootCodec::decode)) {
                is LootCodec.Loot.ShardLoot -> {
                    shards.grant(id = "shard:$slotRef", tier = slot.tier, loot = loot, sourceRef = slotRef)
                    shardTitles += loot.title
                }
                is LootCodec.Loot.DaemonLoot -> {
                    daemons.grant(id = "daemon:$slotRef", loot = loot, sourceRef = slotRef)
                    daemonNames += loot.name
                }
                null -> Unit // payload битый/чужой ключ — тираж не тратим, просто ничего не выдаём
            }
        }

        return RewardOutcome(eddies, shardTitles, daemonNames, exhausted, matchedEffects)
    }

    /**
     * Ручная выдача от живого мастера в обход авто-извлечения (ревизия v9 §6,
     * тир 3 — "ФРАГМЕНТ ИЗВЛЕЧЁН · ТРЕБУЕТСЯ ДЕШИФРОВКА"). Тот же LootCodec/
     * LootCrypto, что и у слота контейнера — просто без демона и без сетки
     * взлома: мастер лично подтвердил выдачу, повторный взлом не нужен.
     * Возвращает описание для тоста, null — если payload битый.
     */
    suspend fun applyGrant(grant: Mb10Qr.LootGrant): String? {
        val lootKey = LootCrypto.deriveKey(settings.gameSecret())
        val loot = LootCrypto.decrypt(grant.encryptedPayload, lootKey)?.let(LootCodec::decode) ?: return null
        return when (loot) {
            is LootCodec.Loot.ShardLoot -> {
                shards.grant(id = "shard:${grant.slotRef}", tier = grant.tier, loot = loot, sourceRef = grant.slotRef)
                "Шард получен: ${loot.title}"
            }
            is LootCodec.Loot.DaemonLoot -> {
                daemons.grant(id = "daemon:${grant.slotRef}", loot = loot, sourceRef = grant.slotRef)
                "Демон получен: ${loot.name}"
            }
        }
    }
}
