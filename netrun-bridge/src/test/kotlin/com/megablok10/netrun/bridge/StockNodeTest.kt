package com.megablok10.netrun.bridge

import com.megablok10.rules.Daemon
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/** `master.stock_node` и `master.unstock_node`: наполнение узла мастером (протокол, раздел 6a). */
class StockNodeTest {
    private fun fx() = ValueFixture(":memory:")
    private fun code(block: () -> Unit): String? = try { block(); null } catch (e: StoreException) { e.code }

    private val daemon = ItemPayloadCodec.encodeDaemon(Daemon("d1", "Призрак", listOf("55", "1C"), Tier.HARD, DaemonEffect.GHOST))
    private fun b64(s: String) = Base64.getEncoder().encodeToString(s.toByteArray())
    private val shard = "SHARD|sh9|0|2|${b64("≈100")}|${b64("Архив")}|${b64("")}|${b64("тело")}|0|0"
    private val stock = listOf(StockItem("DAEMON", daemon), StockItem("SHARD", shard))

    private fun eddies(f: ValueFixture) = VJ.lng(f.store.get("node", "node_07")!!.data, "eddies")

    @Test fun stockCreatesDeterministicItemsAndAddsEddies() {
        val f = fx()
        val r = f.ops.stockNode(f.master, "stock:1", "node_07", stock, 100)
        assertTrue(r.body.toString(), r.ok)
        assertEquals(400L, VJ.lng(r.body, "eddies"))
        assertEquals(400L, eddies(f))
        val ids = VJ.list(r.body, "items")
        assertEquals(2, ids.size)
        assertTrue(ids.all { it.startsWith("it_") && it.length == 19 })
        val d = f.store.get("item", ids[0])!!.data
        assertEquals("node:node_07", VJ.str(d, "owner"))
        assertEquals("master:master-anna", VJ.str(d, "origin"))
        assertEquals(false, VJ.bool(d, "protected"))
        assertNull(VJ.str(d, "handover"))
        assertEquals("GHOST", VJ.str(d["daemon"] as JsonObject, "effect"))
        assertEquals(2L, VJ.lng(f.store.get("item", ids[1])!!.data["shard"] as JsonObject, "tier"))
        // id считается от namespace, rid и индекса
        assertEquals("it_" + VJ.sha256Hex("master/master-anna|stock:1|0").take(16), ids[0])
        assertEquals(emptyList<Violation>(), Auditor(f.store).check())
    }

    @Test fun replayDoesNotDuplicateAndMismatchIsRefused() {
        val f = fx()
        f.ops.stockNode(f.master, "stock:1", "node_07", stock, 100)
        val n = f.store.list("item").size
        val again = f.ops.stockNode(f.master, "stock:1", "node_07", stock, 100)
        assertTrue(again.replayed)
        assertEquals(n, f.store.list("item").size)
        assertEquals(400L, eddies(f))
        assertEquals("rid_mismatch", code { f.ops.stockNode(f.master, "stock:1", "node_07", stock, 50) })
        assertEquals(400L, eddies(f))
    }

    @Test fun rolesAndBadRequests() {
        val f = fx()
        assertEquals("forbidden", code { f.ops.stockNode(f.world, "s1", "node_07", stock, 0) })
        assertEquals("forbidden", code { f.ops.unstockNode(f.world, "u1", "node_07", emptyList(), 5) })
        assertTrue(f.ops.stockNode(f.test, "s2", "node_07", stock, 0).ok)
        assertEquals("not_found", code { f.ops.stockNode(f.master, "s3", "node_99", stock, 0) })
        assertEquals("bad_request", code { f.ops.stockNode(f.master, "s4", "node_07", emptyList(), 0) })
        assertEquals("bad_request", code { f.ops.stockNode(f.master, "s5", "node_07", stock, -1) })
        assertEquals("bad_request", code { f.ops.stockNode(f.master, "s6", "node_07", listOf(StockItem("WEAPON", "x")), 0) })
        assertEquals("bad_request", code { f.ops.stockNode(f.master, "s7", "node_07", listOf(StockItem("SHARD", "")), 0) })
        assertEquals(2 + 6, f.store.list("item").size)
    }

    @Test fun unstockBurnsItemsAndTakesEddies() {
        val f = fx()
        val ids = VJ.list(f.ops.stockNode(f.master, "stock:1", "node_07", stock, 100).body, "items")
        val r = f.ops.unstockNode(f.master, "unstock:1", "node_07", listOf(ids[0], "it_sh1"), 150)
        assertTrue(r.body.toString(), r.ok)
        assertEquals(250L, eddies(f))
        assertEquals("burned:master", f.owner(ids[0]))
        assertEquals("burned:master", f.owner("it_sh1"))
        assertEquals("node:node_07", f.owner(ids[1]))
        assertEquals(emptyList<Violation>(), Auditor(f.store).check())
        assertTrue(f.ops.unstockNode(f.master, "unstock:1", "node_07", listOf(ids[0], "it_sh1"), 150).replayed)
    }

    @Test fun unstockRefusesForeignItemOrTooMuchEddiesAndChangesNothing() {
        val f = fx()
        val before = f.snapshot()
        val r = f.ops.unstockNode(f.master, "u1", "node_07", listOf("it_sh1", "it_dA1"), 0)
        assertEquals("wrong_owner", r.code)
        assertEquals("node:node_07", f.owner("it_sh1"))
        assertEquals("inbox:${f.keyA}", f.owner("it_dA1"))
        assertEquals("bad_request", code { f.ops.unstockNode(f.master, "u2", "node_07", listOf("it_sh1"), 301) })
        assertEquals("bad_request", code { f.ops.unstockNode(f.master, "u3", "node_07", emptyList(), -1) })
        assertEquals("not_found", code { f.ops.unstockNode(f.master, "u4", "node_99", listOf("it_sh1"), 0) })
        assertEquals(300L, eddies(f))
        // изменился только журнал rid отказа
        assertEquals(before.second.filter { it.type != "op_rid" }, f.snapshot().second.filter { it.type != "op_rid" })
    }
}
