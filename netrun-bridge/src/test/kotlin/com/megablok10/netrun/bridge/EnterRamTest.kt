package com.megablok10.netrun.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** RAM при входе (протокол, 6.1 и раздел 8): v1 — `max(6, сумма)` с потолком 13, v2 — `ram` из запроса, отказ `ram_exceeded` с возвратом карточек. */
class EnterRamTest {
    private val test = Caller(Role.TEST, "test")

    private fun BreachFixture.submit(rid: String, key: String, terminal: String, ram: Int?, vararg items: String): OpResult =
        ops.submitDeck(test, rid, key, key, terminal, items.toList(), items.first(), ram)

    private fun BreachFixture.sessionRam(r: OpResult): Long = VJ.lng(session(VJ.str(r.body, "session")!!), "ram")

    @Test fun v1KeepsMaxOfSixAndChainSum() {
        val f = BreachFixture()
        // у B две цепочки по 2 = 4 < 6
        val b = f.submit("enter:b", f.keyB, "t04", null, "it_b1", "it_b2")
        assertTrue(b.body.toString(), b.ok)
        assertEquals(6L, f.sessionRam(b))
        // у A шесть по 2 = 12 > 6
        val a = f.submit("enter:a", f.keyA, "t03", null, *f.daemonsA.map { it.first }.toTypedArray())
        assertTrue(a.body.toString(), a.ok)
        assertEquals(12L, f.sessionRam(a))
    }

    @Test fun v1AboveThirteenIsRamExceededAndCardsGoBack() {
        val f = BreachFixture()
        f.inboxDaemon("it_big", f.keyB, 2)
        f.inboxDaemon("it_long1", f.keyB, 6)
        f.inboxDaemon("it_long2", f.keyB, 6)
        val r = f.submit("enter:b", f.keyB, "t04", null, "it_b1", "it_big", "it_long1", "it_long2") // 2+2+6+6 = 16 > 13
        assertFalse(r.ok)
        assertEquals("ram_exceeded", r.code)
        for (id in listOf("it_b1", "it_big", "it_long1", "it_long2")) assertEquals("outbox:${f.keyB}", f.owner(id))
        assertEquals(4, f.issued.count { it.runner == f.keyB })
        assertEquals(0, f.store.list("session").size)
        // ровно 13 проходит
        f.inboxDaemon("it_ok1", f.keyA, 7)
        f.inboxDaemon("it_ok2", f.keyA, 6)
        val ok = f.submit("enter:a", f.keyA, "t03", null, "it_ok1", "it_ok2")
        assertTrue(ok.body.toString(), ok.ok)
        assertEquals(13L, f.sessionRam(ok))
    }

    @Test fun v2WritesRamFromRequest() {
        val f = BreachFixture()
        val b = f.submit("enter:b", f.keyB, "t04", 9, "it_b1", "it_b2") // сумма 4, RAM 9
        assertTrue(b.body.toString(), b.ok)
        assertEquals(9L, f.sessionRam(b))
        val a = f.submit("enter:a", f.keyA, "t03", 13, *f.daemonsA.map { it.first }.toTypedArray()) // сумма 12 ≤ 13
        assertTrue(a.body.toString(), a.ok)
        assertEquals(13L, f.sessionRam(a))
    }

    @Test fun v2RamMayEqualChainSumAndMinimumIsSix() {
        val f = BreachFixture()
        f.inboxDaemon("it_x", f.keyB, 6)
        val r = f.submit("enter:b", f.keyB, "t04", 6, "it_x")
        assertTrue(r.body.toString(), r.ok)
        assertEquals(6L, f.sessionRam(r))
    }

    @Test fun v2ChainsAboveRamIsRamExceededAndRefundsOnceByRid() {
        val f = BreachFixture()
        val items = f.daemonsA.map { it.first }.toTypedArray() // сумма 12
        val r = f.submit("enter:a", f.keyA, "t03", 8, *items)
        assertFalse(r.ok)
        assertEquals("ram_exceeded", r.code)
        for (id in items) assertEquals("outbox:${f.keyA}", f.owner(id))
        assertEquals(items.size, f.issued.count { it.runner == f.keyA })
        assertEquals(0, f.store.list("session").size)
        // повтор того же rid: тот же отказ, вторых карточек нет
        f.issued.clear()
        val again = f.submit("enter:a", f.keyA, "t03", 8, *items)
        assertTrue(again.replayed)
        assertEquals("ram_exceeded", again.code)
        assertTrue(f.issued.isEmpty())
        assertEquals(emptyList<Violation>(), Auditor(f.store).check())
    }

    @Test fun v2RamOutsideSixToThirteenIsRamExceeded() {
        for ((i, bad) in listOf(5, 14, 0, -1).withIndex()) {
            val f = BreachFixture()
            val r = f.submit("enter:b$i", f.keyB, "t04", bad, "it_b1", "it_b2")
            assertEquals("ram $bad", "ram_exceeded", r.code)
            assertEquals("outbox:${f.keyB}", f.owner("it_b1"))
            assertEquals(0, f.store.list("session").size)
        }
    }

    @Test fun ramGoesIntoRidParamsOnlyWhenGiven() {
        val f = BreachFixture()
        val first = f.submit("enter:b", f.keyB, "t04", null, "it_b1", "it_b2")
        assertTrue(first.ok)
        // повтор v1 с тем же rid — сохранённый ответ (запрос v1, сохранённый до обновления Моста, не даёт rid_mismatch)
        val replay = f.submit("enter:b", f.keyB, "t04", null, "it_b1", "it_b2")
        assertTrue(replay.replayed)
        assertEquals(first.body, replay.body)
        // тот же rid, но уже с ram — другие параметры
        val code = try { f.submit("enter:b", f.keyB, "t04", 8, "it_b1", "it_b2"); "ok" } catch (e: StoreException) { e.code }
        assertEquals("rid_mismatch", code)
        assertNotNull(f.store.get("session", VJ.str(first.body, "session")!!))
    }
}
