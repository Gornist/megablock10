package com.megablok10.app.breach

import com.megablok10.app.collector.CollectorClient
import com.megablok10.app.testing.RoomTest
import com.megablok10.kit.net.LineSocketClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Слот конечного тиража тратится только на лут, который можно выдать: битый, чужой (другой ключ игры) или не того типа payload
 * не заявляется вовсе. Раньше слот сначала заявлялся, потом расшифровывался — и повреждённый QR съедал тираж, ничего не выдав.
 */
@RunWith(RobolectricTestRunner::class)
class LootSlotOrderTest : RoomTest() {
    // settings из RoomTest — без адреса коллектора: заявки на слоты локальные, без сети
    private val slots = SlotClaimStore(db.slotClaimDao(), identity, settings, CollectorClient(), { emptyList() }, LineSocketClient())
    private val rewards = DaemonRewards(wallet, shards, daemons, slots, settings)
    private val key = LootCrypto.deriveKey(null)
    private val extractor = Daemon("d-1", "Экстрактор", listOf("1C", "7A"), Tier.BASE, DaemonEffect.EXTRACT_SHARD)

    private fun shardSlot(title: String, key: ByteArray = this.key) =
        LootSlot(LootType.SHARD, Tier.BASE, copies = 1, payload = LootCrypto.encrypt(LootCodec.encodeShard(title, "", "текст", "", false, 0), key))

    private fun breach(container: Container) = runBlocking {
        rewards.apply(me, container, BreachResult(listOf(extractor), setOf(extractor.id)), attemptId = "${container.id}:1")
    }

    @Test fun brokenPayloadDoesNotConsumeTheSlot() = runBlocking {
        val broken = LootSlot(LootType.SHARD, Tier.BASE, copies = 1, payload = "не base64 и не шифр")
        val container = Container("c-1", "Склад", Tier.BASE, "Арасака", listOf(broken, shardSlot("Чертёж")))

        val outcome = breach(container)

        assertEquals(listOf("Чертёж"), outcome.extractedShardTitles)
        assertEquals("битый слот не заявлен — тираж цел", 0, db.slotClaimDao().claimCount(container.slotRef(0)))
        assertEquals(1, db.slotClaimDao().claimCount(container.slotRef(1)))
        assertNotNull(shards.get("shard:${container.slotRef(1)}"))
    }

    @Test fun lootOfAnotherGameOrWrongTypeIsNotClaimedEither() = runBlocking {
        val otherGame = shardSlot("Чужой", key = LootCrypto.deriveKey("код другой игры"))
        val daemonInShardSlot = LootSlot(LootType.SHARD, Tier.BASE, 1, LootCrypto.encrypt(LootCodec.encodeDaemon("Тень", listOf("1C"), Tier.BASE, DaemonEffect.MINER), key))
        val container = Container("c-2", "Склад", Tier.BASE, "Арасака", listOf(otherGame, daemonInShardSlot))

        val outcome = breach(container)

        assertEquals(emptyList<String>(), outcome.extractedShardTitles)
        assertEquals(0, db.slotClaimDao().claimCount(container.slotRef(0)))
        assertEquals(0, db.slotClaimDao().claimCount(container.slotRef(1)))
        assertNull(shards.get("shard:${container.slotRef(0)}"))
    }
}
