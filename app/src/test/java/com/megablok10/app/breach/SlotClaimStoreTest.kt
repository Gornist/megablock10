package com.megablok10.app.breach

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Чистая логика выбора слота (SlotClaimStore.pickSlot) — эксклюзивность тиража ревизии v9 §6, без Context/БД. */
class SlotClaimStoreTest {
    private val container = Container(
        id = "container-1", name = "Панель", tier = Tier.NIGHTMARE, ownerFaction = "Otryad_SB",
        loot = listOf(
            LootSlot(type = LootType.SHARD, tier = Tier.BASE, copies = 2, payload = ""),
            LootSlot(type = LootType.DAEMON, tier = Tier.HARD, copies = 1, payload = ""),
            LootSlot(type = LootType.SHARD, tier = Tier.NIGHTMARE, copies = 0, payload = "")
        )
    )

    @Test
    fun `picks the first matching slot with copies remaining`() = runBlocking {
        val index = SlotClaimStore.pickSlot(container, LootType.SHARD, Tier.NIGHTMARE, emptySet()) { 0 }
        assertEquals(0, index)
    }

    @Test
    fun `skips a slot already exhausted by claim count and falls through to the next one`() = runBlocking {
        val index = SlotClaimStore.pickSlot(container, LootType.SHARD, Tier.NIGHTMARE, emptySet()) { slotRef ->
            if (slotRef == "container-1#0") 2 else 0
        }
        assertEquals(2, index)
    }

    @Test
    fun `copies of 0 means unlimited and is never treated as exhausted`() = runBlocking {
        val index = SlotClaimStore.pickSlot(container, LootType.SHARD, Tier.NIGHTMARE, emptySet()) { slotRef ->
            if (slotRef == "container-1#0") 2 else 999
        }
        assertEquals(2, index)
    }

    @Test
    fun `excludeIndices skips slots already claimed earlier in the same attempt`() = runBlocking {
        val index = SlotClaimStore.pickSlot(container, LootType.SHARD, Tier.NIGHTMARE, setOf(0)) { 0 }
        assertEquals(2, index)
    }

    @Test
    fun `a low-tier extractor cannot reach a higher-tier slot even once lower ones are exhausted`() = runBlocking {
        val index = SlotClaimStore.pickSlot(container, LootType.SHARD, Tier.BASE, emptySet()) { slotRef ->
            if (slotRef == "container-1#0") 2 else 0
        }
        assertNull(index) // слот #0 (BASE) исчерпан, слот #2 (NIGHTMARE) экстрактору тира BASE не по силам
    }

    @Test
    fun `no matching slot type returns null`() = runBlocking {
        assertNull(SlotClaimStore.pickSlot(container, LootType.DAEMON, Tier.BASE, emptySet()) { 0 })
    }

    @Test
    fun `all slots exhausted returns null`() = runBlocking {
        assertNull(SlotClaimStore.pickSlot(container, LootType.SHARD, Tier.NIGHTMARE, setOf(0, 2)) { 0 })
    }
}
