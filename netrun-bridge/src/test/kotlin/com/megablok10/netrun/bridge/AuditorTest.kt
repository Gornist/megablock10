package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AuditorTest {
    private fun fx() = ValueFixture(":memory:")
    private fun alerts(f: ValueFixture) = f.store.list("alert")

    @Test fun cleanStoreHasNoViolationsAndNoAlerts() {
        val f = fx()
        f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        assertEquals(emptyList<Violation>(), Auditor(f.store).run())
        assertTrue(alerts(f).isEmpty())
    }

    @Test fun deckOwnerOfClosedOrMissingSessionIsFound() {
        val f = fx()
        val it = f.store.get("item", "it_sh1")!!
        f.store.put("item", it.id, it.ver, VJ.with(it.data, "owner" to JsonPrimitive("deck:s_nope")))
        val found = Auditor(f.store).run()
        assertTrue(found.toString(), found.any { v -> v.kind == "item_owner" && v.items == listOf("it_sh1") })
        assertTrue(found.any { v -> v.kind == "deck_items" })
        assertTrue(alerts(f).all { VJ.str(it.data, "msg")!!.isNotEmpty() })
    }

    @Test fun itemInTwoDecksOrMissingFromDeckIsFound() {
        val f = fx()
        val a = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val b = f.enterActive(f.keyB, "t04", "it_dB1", "it_dB2")
        val deckB = f.store.get("deck", b)!!
        f.store.put("deck", b, deckB.ver, VJ.with(deckB.data, "items" to VJ.arr(listOf("it_dB1", "it_dB2", "it_dA2"))))
        val found = Auditor(f.store).check()
        assertTrue(found.toString(), found.any { it.kind == "deck_items" && it.subject == b && "it_dA2" in it.items })
        val deckA = f.store.get("deck", a)!!
        f.store.put("deck", a, deckA.ver, VJ.with(deckA.data, "items" to VJ.arr(listOf("it_dA1"))))
        assertTrue(Auditor(f.store).check().any { it.subject == a && "it_dA2" in it.items })
    }

    @Test fun ownerlessItemAndOutboxWithoutCardAreFound() {
        val f = fx()
        val x = f.store.get("item", "it_sh1")!!
        f.store.put("item", x.id, x.ver, VJ.with(x.data, "owner" to kotlinx.serialization.json.JsonNull))
        val y = f.store.get("item", "it_sh2")!!
        f.store.put("item", y.id, y.ver, VJ.with(y.data, "owner" to JsonPrimitive("outbox:K"), "out_transfer" to kotlinx.serialization.json.JsonNull))
        val ids = Auditor(f.store).check().filter { it.kind == "item_owner" }.flatMap { it.items }.toSet()
        assertEquals(setOf("it_sh1", "it_sh2"), ids)
    }

    @Test fun negativeAndStuckEddiesAreFound() {
        val f = fx()
        val n = f.store.get("node", "node_07")!!
        f.store.put("node", n.id, n.ver, VJ.with(n.data, "eddies" to JsonPrimitive(-5L)))
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val s = f.store.get("session", sid)!!
        f.store.put("session", sid, s.ver, VJ.with(s.data, "state" to JsonPrimitive("closed"), "loot_eddies" to JsonPrimitive(40L)))
        val kinds = Auditor(f.store).check().map { it.subject }
        assertTrue(kinds.toString(), "node:node_07" in kinds && "stuck:$sid" in kinds)
    }

    @Test fun alertsAreNotDuplicatedAndReturnAfterMasterDeletesThem() {
        val f = fx()
        val it = f.store.get("item", "it_sh1")!!
        f.store.put("item", it.id, it.ver, VJ.with(it.data, "owner" to JsonPrimitive("bogus:1")))
        val auditor = Auditor(f.store)
        auditor.run()
        val n = alerts(f).size
        assertTrue(n > 0)
        auditor.run()
        assertEquals(n, alerts(f).size)
        val al = alerts(f).first()
        f.store.delete("alert", al.id, al.ver)
        auditor.run()
        assertEquals(n, alerts(f).size)
    }

    @Test fun periodicRunWritesAlert() {
        val f = fx()
        val it = f.store.get("item", "it_sh1")!!
        f.store.put("item", it.id, it.ver, VJ.with(it.data, "owner" to JsonPrimitive("bogus:1")))
        Auditor(f.store).use { a ->
            a.start(1)
            val end = System.currentTimeMillis() + 10_000
            while (alerts(f).isEmpty() && System.currentTimeMillis() < end) Thread.sleep(50)
            assertTrue(alerts(f).isNotEmpty())
        }
    }
}
