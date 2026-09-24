package com.megablok10.app.breach

import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
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
        // Содержимое слотов — до заявки на слот: битый или чужой (другая игра, другой ключ) payload, как и лут не того типа,
        // что объявлен в слоте, выдать нельзя, и тратить на него конечный тираж тоже нельзя — такие слоты не заявляются вовсе.
        val contents = container.loot.map { slot -> LootCrypto.decrypt(slot.payload, lootKey)?.let(LootCodec::decode)?.takeIf { it.type == slot.type } }
        val unusable = contents.indices.filter { contents[it] == null }.toSet()
        if (unusable.isNotEmpty() && matched.any { it.effect == DaemonEffect.EXTRACT_SHARD || it.effect == DaemonEffect.EXTRACT_DAEMON }) {
            Mb10Log.warnEvent("Rewards", "loot.unreadable_slots", "container" to container.id, "slots" to unusable.joinToString(","))
        }
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
            val slotIndex = slotClaims.claimNextAvailable(identity, container, lootType, daemon.tier, claimedThisAttempt + unusable)
            if (slotIndex == null) {
                exhausted = true
                return@forEach
            }
            claimedThisAttempt += slotIndex
            val slot = container.loot[slotIndex]
            val slotRef = container.slotRef(slotIndex)
            when (val loot = contents[slotIndex]) {
                is LootCodec.Loot.ShardLoot -> {
                    shards.grant(id = "shard:$slotRef", tier = slot.tier, loot = loot, sourceRef = slotRef)
                    shardTitles += loot.title
                }
                is LootCodec.Loot.DaemonLoot -> {
                    daemons.grant(id = "daemon:$slotRef", loot = loot, sourceRef = slotRef)
                    daemonNames += loot.name
                }
                null -> Unit // не бывает: такие слоты исключены из заявки выше
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

/** Какой тип слота это содержимое заполняет. */
private val LootCodec.Loot.type: LootType
    get() = when (this) {
        is LootCodec.Loot.ShardLoot -> LootType.SHARD
        is LootCodec.Loot.DaemonLoot -> LootType.DAEMON
    }
