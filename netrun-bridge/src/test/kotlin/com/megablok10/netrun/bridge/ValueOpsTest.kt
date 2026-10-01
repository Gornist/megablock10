package com.megablok10.netrun.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.sql.DriverManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ValueOpsTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun fx() = ValueFixture(":memory:")
    private fun code(block: () -> Unit): String? = try { block(); null } catch (e: StoreException) { e.code }

    // ---------- сквозной сценарий ----------

    @Test fun cleanRunReturnsEverythingToThePhone() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.assertConserved()
        assertTrue(f.ops.takeFromNode(f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1").ok)
        assertTrue(f.ops.takeFromNode(f.world, "take:$sid:eddies:1", sid, "node_07", null, 50).ok)
        f.assertConserved()
        assertEquals("deck:$sid", f.owner("it_sh1"))
        assertEquals(250L, VJ.lng(f.store.get("node", "node_07")!!.data, "eddies"))
        f.issued.clear()
        val moves = listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE))
        val r = f.ops.finishRun(f.world, "finish:$sid", sid, "clean", "node_07", false, moves)
        assertTrue(r.body.toString(), r.ok)
        for (i in listOf("it_dA1", "it_dA2", "it_sh1")) assertEquals("outbox:${f.keyA}", f.owner(i))
        assertEquals(4, f.issued.size) // 3 предмета и эдди
        assertEquals(50L, f.issued.single { it.item == null }.eddies)
        val s = f.store.get("session", sid)!!
        assertEquals("closed", VJ.str(s.data, "state"))
        assertEquals(0L, VJ.lng(s.data, "loot_eddies"))
        assertEquals(emptyList<String>(), VJ.list(f.store.get("deck", sid)!!.data, "items"))
        assertEquals(2L, VJ.lng(f.store.get("runner", ValueOps.runnerDocId(f.keyA))!!.data, "runs"))
        f.assertConserved()
    }

    @Test fun blackIceBurnsNothingKeepsProtectedAndBlocksRunner() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.ops.takeFromNode(f.world, "t1", sid, "node_07", "it_sh1")
        f.ops.takeFromNode(f.world, "t2", sid, "node_07", null, 70)
        val moves = listOf(Move("it_dA2", MoveTo.NODE), Move("it_sh1", MoveTo.NODE))
        val r = f.ops.finishRun(f.world, "finish:$sid", sid, "black_ice", "node_07", true, moves)
        assertTrue(r.body.toString(), r.ok)
        assertEquals("outbox:${f.keyA}", f.owner("it_dA1")) // защищённый демон не теряется
        assertEquals("node:node_07", f.owner("it_dA2"))
        assertEquals(300L, VJ.lng(f.store.get("node", "node_07")!!.data, "eddies")) // добыча эдди вернулась в узел
        assertTrue(VJ.bool(f.store.get("runner", ValueOps.runnerDocId(f.keyA))!!.data, "blocked"))
        assertTrue(f.store.list("alert").any { VJ.str(it.data, "kind") == "flatline" })
        f.assertConserved()
        // заблокированный игрок: вход отказан, сданное возвращается на телефон в той же транзакции
        val again = f.ops.submitDeck(f.test, "enter:e-2", f.keyA, "A", "t03", listOf("it_dA1"), "it_dA1")
        assertFalse(again.ok)
    }

    @Test fun softIceLocksNodeAndLootStaysInNode() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.ops.takeFromNode(f.world, "t1", sid, "node_07", "it_sh1")
        val moves = listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.NODE))
        assertTrue(f.ops.finishRun(f.world, "finish:$sid", sid, "soft_ice", "node_07", false, moves).ok)
        assertTrue(VJ.lng(f.store.get("node", "node_07")!!.data, "lockdown_until") > 1_000L)
        assertEquals("node:node_07", f.owner("it_sh1"))
        f.assertConserved()
    }

    @Test fun finishViolationsAreBadRequestAndChangeNothing() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.ops.takeFromNode(f.world, "t1", sid, "node_07", "it_sh1")
        val before = f.snapshot()
        // чистый выход: добыча не может остаться в узле
        assertEquals("bad_request", code { f.ops.finishRun(f.world, "f1", sid, "clean", "node_07", false, listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.NODE))) })
        // предмет деки не упомянут
        assertEquals("bad_request", code { f.ops.finishRun(f.world, "f2", sid, "clean", "node_07", false, listOf(Move("it_dA2", MoveTo.PHONE))) })
        // защищённого нельзя сжечь
        val moves = listOf(Move("it_dA1", MoveTo.BURNED), Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE))
        val r = f.ops.finishRun(f.world, "f3", sid, "emergency", "node_07", false, moves)
        assertEquals("protected_item", r.code)
        assertEquals("bad_request", code { f.ops.finishRun(f.world, "f4", sid, "aborted", "node_07", false, emptyList()) })
        assertEquals(before.second.filter { it.type != "op_rid" }, f.snapshot().second.filter { it.type != "op_rid" })
    }

    @Test fun emergencyMayBurnADemonButNotLoot() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.ops.takeFromNode(f.world, "t1", sid, "node_07", "it_sh1")
        assertEquals("bad_request", code { f.ops.finishRun(f.world, "f1", sid, "emergency", "node_07", false, listOf(Move("it_dA2", MoveTo.BURNED), Move("it_sh1", MoveTo.BURNED))) })
        assertTrue(f.ops.finishRun(f.world, "f2", sid, "emergency", "node_07", false, listOf(Move("it_dA2", MoveTo.BURNED), Move("it_sh1", MoveTo.NODE))).ok)
        assertEquals("burned:$sid", f.owner("it_dA2"))
        f.assertConserved()
    }

    @Test fun leaveAndTakeAndProtected() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        assertEquals("protected_item", f.ops.leaveInNode(f.world, "l1", sid, "node_07", "it_dA1").code)
        assertTrue(f.ops.leaveInNode(f.world, "l2", sid, "node_07", "it_dA2").ok)
        assertEquals("node:node_07", f.owner("it_dA2"))
        assertEquals(listOf("it_dA1"), VJ.list(f.store.get("deck", sid)!!.data, "items"))
        assertEquals("wrong_owner", f.ops.leaveInNode(f.world, "l3", sid, "node_07", "it_dA2").code)
        assertTrue(f.ops.takeFromNode(f.world, "t1", sid, "node_07", "it_dA2").ok)
        f.assertConserved()
    }

    @Test fun issueToPhoneAndPermissions() {
        val f = fx()
        val r = f.ops.issueToPhone(f.master, "give:1", f.keyA, listOf("it_sh1"), 0, "ручная выдача")
        assertTrue(r.body.toString(), r.ok)
        assertEquals("outbox:${f.keyA}", f.owner("it_sh1"))
        assertEquals("PENDING", VJ.str(f.store.get("item", "it_sh1")!!.data, "handover"))
        // сервер мира: предмет из узла и эмиссия эдди запрещены
        assertEquals("wrong_owner", f.ops.issueToPhone(f.world, "give:2", f.keyA, listOf("it_sh2"), 0, "x").code)
        assertEquals("forbidden", code { f.ops.issueToPhone(f.world, "give:3", f.keyA, emptyList(), 10, "x") })
        // защищённый демон чужому игроку
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        assertEquals("wrong_owner", f.ops.issueToPhone(f.world, "give:4", f.keyB, listOf("it_dA1"), 0, "x").code)
        val sh2 = f.store.get("item", "it_sh2")!!
        f.store.put("item", sh2.id, sh2.ver, VJ.with(sh2.data, "protected" to kotlinx.serialization.json.JsonPrimitive(true), "origin" to kotlinx.serialization.json.JsonPrimitive("phone:${f.keyA}")))
        assertEquals("protected_item", f.ops.issueToPhone(f.master, "give:4b", f.keyB, listOf("it_sh2"), 0, "x").code)
        assertTrue(f.ops.issueToPhone(f.master, "give:4c", f.keyA, listOf("it_sh2"), 0, "x").ok)
        assertEquals("wrong_owner", f.ops.issueToPhone(f.world, "give:5", f.keyB, listOf("it_dA2"), 0, "x").code)
        // сдача деки — только test и сам Мост
        assertEquals("forbidden", code { f.ops.submitDeck(f.master, "e", f.keyB, "B", "t04", listOf("it_dB1"), "it_dB1") })
        assertEquals("forbidden", code { f.ops.submitDeck(f.world, "e", f.keyB, "B", "t04", listOf("it_dB1"), "it_dB1") })
        assertNotNull(sid)
    }

    @Test fun submitRefusalRefundsInSameTransaction() {
        val f = fx()
        f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        // терминал t03 занят: дека B уходит обратно на телефон
        val r = f.ops.submitDeck(f.test, "enter:e-b", f.keyB, "B", "t03", listOf("it_dB1", "it_dB2"), "it_dB1")
        assertEquals("session_state", r.code)
        assertEquals("outbox:${f.keyB}", f.owner("it_dB1"))
        assertEquals("outbox:${f.keyB}", f.owner("it_dB2"))
        assertEquals(2, f.issued.count { it.runner == f.keyB })
        // повтор отказа не выдаёт карточки второй раз
        f.issued.clear()
        val again = f.ops.submitDeck(f.test, "enter:e-b", f.keyB, "B", "t03", listOf("it_dB1", "it_dB2"), "it_dB1")
        assertTrue(again.replayed)
        assertTrue(f.issued.isEmpty())
        f.assertConserved()
    }

    @Test fun abortReturnsDeckOnce() {
        val f = fx()
        val r = f.ops.submitDeck(f.test, "enter:e1", f.keyA, "A", "t03", listOf("it_dA1", "it_dA2"), "it_dA1")
        val sid = f.sessionOf(r)
        assertTrue(f.ops.abortSession(f.world, sid, "отказ").ok)
        assertEquals("outbox:${f.keyA}", f.owner("it_dA1"))
        assertEquals("aborted", VJ.str(f.store.get("session", sid)!!.data, "outcome"))
        assertTrue(f.ops.abortSession(f.world, sid, "отказ").replayed)
        f.assertConserved()
    }

    // ---------- повтор ----------

    @Test fun replayReturnsSameAnswerWithoutExecutingAgain() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val first = f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
        val seq = f.store.seq
        val second = f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
        assertTrue(second.replayed)
        assertFalse(first.replayed)
        assertEquals(first.body, second.body)
        assertEquals(seq, f.store.seq) // записей нет вообще
        // даже когда предмет с тех пор вернулся в узел, повтор отвечает сохранённым ответом и не берёт его снова
        f.ops.leaveInNode(f.world, "leave:1", sid, "node_07", "it_sh1")
        val third = f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
        assertTrue(third.replayed)
        assertEquals("node:node_07", f.owner("it_sh1"))
        // эдди: повтор не списывает второй раз
        f.ops.takeFromNode(f.world, "take:e", sid, "node_07", null, 40)
        f.ops.takeFromNode(f.world, "take:e", sid, "node_07", null, 40)
        assertEquals(260L, VJ.lng(f.store.get("node", "node_07")!!.data, "eddies"))
        f.assertConserved()
    }

    @Test fun sameRidWithOtherParamsIsMismatchAndDoesNothing() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
        val before = f.snapshot()
        assertEquals("rid_mismatch", code { f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh2") })
        assertEquals(before, f.snapshot())
        // другое пространство имён — другой rid, хотя строка та же
        assertTrue(f.ops.takeFromNode(f.master, "take:1", sid, "node_07", "it_sh2").ok)
    }

    @Test fun errorAnswerIsStoredAndReplayed() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val e1 = f.ops.leaveInNode(f.world, "l1", sid, "node_07", "it_sh1")
        assertEquals("wrong_owner", e1.code)
        assertNotNull(e1.doc)
        f.ops.takeFromNode(f.world, "t", sid, "node_07", "it_sh1")
        f.ops.leaveInNode(f.world, "l0", sid, "node_07", "it_sh1")
        val e2 = f.ops.leaveInNode(f.world, "l1", sid, "node_07", "it_sh1")
        assertTrue(e2.replayed)
        assertEquals(e1.body, e2.body)
    }

    @Test fun replayAfterRestartStillWorks() {
        val path = tmp.root.resolve("restart.db").path
        val f = ValueFixture(path)
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val first = f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
        f.store.close()
        val store2 = DocStore.open(path)
        val second = ValueOps(store2).takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
        assertTrue(second.replayed)
        assertEquals(first.body, second.body)
        store2.close()
    }

    // ---------- обрыв посреди операции ----------

    /** Сбой на каждом вызове часов внутри операции: ничего не изменилось, повтор с тем же rid проходит. */
    private fun sweep(setup: ValueFixture.() -> Unit, op: ValueFixture.() -> OpResult) {
        val ref = fx().also { it.setup(); it.calls = 0 }
        val expected = ref.op()
        val n = ref.calls
        assertTrue("операция не трогала часы", n > 0)
        for (k in 1..n) {
            val f = fx()
            f.setup()
            val before = f.snapshot()
            f.calls = 0
            f.failAt = k
            try { f.op(); fail("сбой $k не сработал") } catch (e: IllegalStateException) { assertTrue(e.message!!.contains("сбой")) }
            f.failAt = -1
            assertEquals("сбой на вызове $k оставил следы", before, f.snapshot())
            f.assertConserved()
            f.issued.clear()
            val r = f.op()
            assertFalse(r.replayed)
            assertEquals(expected.ok, r.ok)
            assertEquals(expected.code, r.code)
            assertEquals(expected.body["transfers"], r.body["transfers"])
            f.assertConserved()
        }
    }

    private fun active(f: ValueFixture) = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")

    @Test fun faultSweepSubmitDeck() = sweep({}) { ops.submitDeck(test, "enter:e1", keyA, "A", "t03", listOf("it_dA1", "it_dA2"), "it_dA1") }

    @Test fun faultSweepSubmitRefusal() = sweep({ enterActive(keyA, "t03", "it_dA1", "it_dA2") }) {
        ops.submitDeck(test, "enter:e-b", keyB, "B", "t03", listOf("it_dB1", "it_dB2"), "it_dB1")
    }

    @Test fun faultSweepTakeItem() {
        var sid = ""
        sweep({ sid = active(this) }) { ops.takeFromNode(world, "take:1", sid, "node_07", "it_sh1") }
    }

    @Test fun faultSweepTakeEddies() {
        var sid = ""
        sweep({ sid = active(this) }) { ops.takeFromNode(world, "take:1", sid, "node_07", null, 60) }
    }

    @Test fun faultSweepLeave() {
        var sid = ""
        sweep({ sid = active(this); ops.takeFromNode(world, "t", sid, "node_07", "it_sh1") }) {
            ops.leaveInNode(world, "leave:1", sid, "node_07", "it_sh1")
        }
    }

    @Test fun faultSweepIssue() = sweep({}) { ops.issueToPhone(master, "give:1", keyA, listOf("it_sh1", "it_dA1"), 0, "x") }

    @Test fun faultSweepAbort() {
        var sid = ""
        sweep({ sid = sessionOf(ops.submitDeck(test, "enter:e1", keyA, "A", "t03", listOf("it_dA1", "it_dA2"), "it_dA1")) }) {
            ops.abortSession(world, sid, "x")
        }
    }

    @Test fun faultSweepFinishClean() {
        var sid = ""
        val setup: ValueFixture.() -> Unit = {
            sid = active(this)
            ops.takeFromNode(world, "t1", sid, "node_07", "it_sh1")
            ops.takeFromNode(world, "t2", sid, "node_07", null, 80)
        }
        sweep(setup) {
            ops.finishRun(world, "finish:$sid", sid, "clean", "node_07", false, listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE)))
        }
    }

    @Test fun faultSweepFinishBlackIce() {
        var sid = ""
        val setup: ValueFixture.() -> Unit = {
            sid = active(this)
            ops.takeFromNode(world, "t1", sid, "node_07", "it_sh1")
            ops.takeFromNode(world, "t2", sid, "node_07", null, 80)
        }
        sweep(setup) {
            ops.finishRun(world, "finish:$sid", sid, "black_ice", "node_07", false, listOf(Move("it_dA2", MoveTo.NODE), Move("it_sh1", MoveTo.NODE)))
        }
    }

    /** Сбой SQLite на коммите: транзакция откатывается целиком, память не меняется, после починки повтор проходит. */
    @Test fun sqliteFailureDuringCommitLeavesNothing() {
        val path = tmp.root.resolve("fail.db").path
        val f = ValueFixture(path)
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val before = f.snapshot()
        DriverManager.getConnection("jdbc:sqlite:$path").use { c -> c.createStatement().use { it.execute("DROP TABLE meta") } }
        try {
            f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
            fail("ожидали сбой SQLite")
        } catch (e: StoreException) {
            assertEquals("internal", e.code)
        }
        assertEquals(before, f.snapshot())
        f.assertConserved()
        // на диске тоже ничего: открываем заново и сравниваем
        DriverManager.getConnection("jdbc:sqlite:$path").use { c ->
            c.createStatement().use { it.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL)") }
        }
        val onDisk = DocStore.open(path)
        assertEquals("deck:$sid".let { "node:node_07" }, VJ.str(onDisk.get("item", "it_sh1")!!.data, "owner"))
        assertNull(onDisk.get("op_rid", VJ.sha256Hex("test/test|take:1")))
        onDisk.close()
        // после починки тот же rid выполняется
        f.issued.clear()
        // seq в meta потерян вместе с таблицей, поэтому свежий счёт; важно лишь, что операция проходит
        assertTrue(f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1").ok)
    }

    @Test fun gatewayFailureDoesNotUndoCommit() {
        val f = fx()
        val ops = ValueOps(f.store, f.clock) { error("M2 упал") }
        val r = ops.issueToPhone(f.master, "give:1", f.keyA, listOf("it_sh1"), 0, "x")
        assertTrue(r.ok)
        assertEquals("outbox:${f.keyA}", f.owner("it_sh1"))
    }

    // ---------- гонки ----------

    @Test fun twoSessionsRaceForOneItem() {
        repeat(30) {
            val f = fx()
            val sA = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
            val sB = f.enterActive(f.keyB, "t04", "it_dB1", "it_dB2")
            val results = race(2) { i ->
                if (i == 0) f.ops.takeFromNode(f.world, "take:$sA:it_sh1", sA, "node_07", "it_sh1")
                else f.ops.takeFromNode(f.world, "take:$sB:it_sh1", sB, "node_07", "it_sh1")
            }
            assertEquals(1, results.count { it.ok })
            val loser = results.single { !it.ok }
            assertEquals("wrong_owner", loser.code)
            assertTrue(f.owner("it_sh1") == "deck:$sA" || f.owner("it_sh1") == "deck:$sB")
            f.assertConserved()
        }
    }

    @Test fun manyThreadsRaceForEddiesNeverGoNegative() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.ops.takeFromNode(f.world, "drain", sid, "node_07", null, 200) // осталось 100
        val results = race(10) { i -> f.ops.takeFromNode(f.world, "e:$i", sid, "node_07", null, 20) }
        assertEquals(5, results.count { it.ok })
        assertEquals(0L, VJ.lng(f.store.get("node", "node_07")!!.data, "eddies"))
        f.assertConserved()
    }

    @Test fun sameRidFromManyThreadsExecutesOnce() {
        val f = fx()
        val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        val results = race(8) { f.ops.takeFromNode(f.world, "take:1", sid, "node_07", null, 30) }
        assertEquals(1, results.count { !it.replayed })
        assertEquals(270L, VJ.lng(f.store.get("node", "node_07")!!.data, "eddies"))
        f.assertConserved()
    }

    @Test fun takeAndIssueRaceForOneItem() {
        repeat(30) {
            val f = fx()
            val sid = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
            val results = race(2) { i ->
                if (i == 0) f.ops.takeFromNode(f.world, "take:1", sid, "node_07", "it_sh1")
                else f.ops.issueToPhone(f.master, "give:1", f.keyB, listOf("it_sh1"), 0, "x")
            }
            assertEquals(1, results.count { it.ok })
            f.assertConserved()
        }
    }

    private fun race(n: Int, body: (Int) -> OpResult): List<OpResult> {
        val pool = Executors.newFixedThreadPool(n)
        val start = CountDownLatch(1)
        try {
            val futures = (0 until n).map { i -> pool.submit<OpResult> { start.await(); body(i) } }
            start.countDown()
            return futures.map { it.get(30, TimeUnit.SECONDS) }
        } finally {
            pool.shutdownNow()
        }
    }
}
