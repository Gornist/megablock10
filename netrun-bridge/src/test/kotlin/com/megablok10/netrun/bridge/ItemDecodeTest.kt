package com.megablok10.netrun.bridge

import com.megablok10.rules.Daemon
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.ShardPayload
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Поле `daemon`/`shard` документа `item`: из payload карточки, для уже лежащих документов — дописывается при старте Моста. */
class ItemDecodeTest {
    private fun payload(effect: DaemonEffect, tier: Tier) = ItemPayloadCodec.encodeDaemon(Daemon("d", "Призрак", listOf("55", "1C"), tier, effect))

    private fun item(kind: String, payload: String) =
        VJ.obj("owner" to VJ.p("deck:s1"), "kind" to VJ.p(kind), "payload" to VJ.p(payload), "protected" to VJ.p(false))

    @Test fun daemonFieldCarriesEffectAndTier() {
        val d = ItemDecode.fields("DAEMON", payload(DaemonEffect.GHOST, Tier.NIGHTMARE)).getValue("daemon")
        assertEquals("GHOST", VJ.str(d, "effect"))
        assertEquals(3L, VJ.lng(d, "tier"))
        assertEquals("Призрак", VJ.str(d, "name"))
    }

    private fun shardPayload(decryptAction: Boolean, decrypted: Boolean) =
        ItemPayloadCodec.encodeShard(ShardPayload("s", decryptAction, 1, "подсказка", "Шард", "мета", "тело", 0, decrypted))

    @Test fun shardEncryptedOnlyWithDecryptActionAndNotDecrypted() {
        fun enc(a: Boolean, d: Boolean) = VJ.bool(ItemDecode.fields("SHARD", shardPayload(a, d)).getValue("shard"), "encrypted")
        assertEquals(true, enc(true, false))
        assertEquals(false, enc(false, false)) // без действия расшифровки «РАСШИФРОВАТЬ» не предлагается
        assertEquals(false, enc(true, true))
    }

    @Test fun enrichAddsEncryptedToShardDocumentsThatLackIt() {
        val old = item("SHARD", shardPayload(false, false)).let {
            JsonObject(it + ("shard" to VJ.obj("tier" to VJ.p(1L), "title" to VJ.p("Шард"), "decrypted" to VJ.p(false))))
        }
        val next = ItemDecode.enrich(old)!!
        assertEquals(false, VJ.bool(next["shard"] as JsonObject, "encrypted"))
        assertNull(ItemDecode.enrich(next)) // повтор ничего не меняет
    }

    @Test fun garbageAndUnknownKindGiveNothing() {
        assertTrue(ItemDecode.fields("DAEMON", "мусор").isEmpty())
        assertTrue(ItemDecode.fields("SHARD", payload(DaemonEffect.GHOST, Tier.BASE)).isEmpty())
        assertTrue(ItemDecode.fields("OTHER", "x").isEmpty())
        assertNull(ItemDecode.enrich(item("DAEMON", "мусор")))
    }

    @Test fun backfillFillsExistingDocumentsOnceAndSkipsReady() {
        val store = DocStore.open(":memory:")
        store.put("item", "a", 0, item("DAEMON", payload(DaemonEffect.JITTER, Tier.HARD)))
        store.put("item", "bad", 0, item("DAEMON", "p-bad"))
        assertEquals(1, ItemDecode.backfill(store))
        val a = store.get("item", "a")!!
        assertEquals("JITTER", VJ.str(a.data["daemon"] as JsonObject, "effect"))
        assertEquals(2L, a.ver)
        assertNull(store.get("item", "bad")!!.data["daemon"])
        assertEquals(0, ItemDecode.backfill(store)) // повтор ничего не меняет
        assertEquals(2L, store.get("item", "a")!!.ver)
        store.close()
    }
}
