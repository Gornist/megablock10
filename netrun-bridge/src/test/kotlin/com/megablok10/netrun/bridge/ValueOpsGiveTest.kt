package com.megablok10.netrun.bridge

import com.megablok10.kit.crypto.Ecdsa
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * `op.give_item` (протокол, 6.7): груз уходит другому нетраннеру в Сети или на телефон; рабочие и защищённые демоны остаются.
 * Операция двигает ценности, поэтому после каждого шага сверяем: предметов столько же, у каждого один владелец, аудитор чист.
 */
class ValueOpsGiveTest {
    @get:Rule val tmp = TemporaryFolder()

    private val phoneKey = Ecdsa.encodeKey(Ecdsa.generateKeyPair().public)

    /** Два игрока в Сети: A (терминал t03) и B (t04); у A в грузе шарды `it_sh1`, `it_sh2` и демон `it_dx` из узла. */
    private class Stand(val f: ValueFixture) {
        val a: String
        val b: String
        val total: Int

        init {
            f.item("it_dx", "node:node_07", "node:node_07", kind = "DAEMON")
            a = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
            b = f.enterActive(f.keyB, "t04", "it_dB1", "it_dB2")
            for (id in listOf("it_sh1", "it_sh2", "it_dx")) {
                assertTrue(f.ops.takeFromNode(f.world, "take:$a:$id", a, "node_07", id).ok)
            }
            total = f.store.list("item").size
            f.calls = 0
        }

        fun ver(item: String): Long = f.store.get("item", item)!!.ver

        fun rid(session: String, item: String): String = "give:$session:$item:${ver(item)}"

        fun give(session: String, item: String, to: GiveTarget, rid: String = rid(session, item), ver: Long = ver(item)): OpResult =
            f.ops.giveItem(f.world, rid, session, item, ver, to)

        fun deck(session: String): List<String> = VJ.list(f.store.get("deck", session)!!.data, "items")

        fun conserved() {
            assertEquals(total, f.store.list("item").size)
            assertEquals(emptyList<Violation>(), Auditor(f.store).check())
            for (d in f.store.list("deck")) {
                val owned = f.store.list("item").filter { VJ.str(it.data, "owner") == "deck:${d.id}" }.map { it.id }.toSet()
                assertEquals("deck ${d.id}", owned, VJ.list(d.data, "items").toSet())
            }
        }
    }

    private fun stand() = Stand(ValueFixture(":memory:"))

    private fun code(block: () -> Unit): String? = try { block(); null } catch (e: StoreException) { e.code }

    // ---------- получатель — нетраннер в Сети ----------

    @Test fun giveToSessionMovesOwnerAndBothDecksInOneTransaction() {
        val s = stand()
        val before = s.f.store.get("item", "it_sh1")!!
        val r = s.give(s.a, "it_sh1", GiveTarget.Session(s.b))
        assertTrue(r.body.toString(), r.ok)
        assertFalse(r.replayed)
        assertEquals("deck:${s.b}", VJ.str(r.body, "to"))
        assertEquals(null, VJ.str(r.body, "transfer"))
        val item = s.f.store.get("item", "it_sh1")!!
        assertEquals("deck:${s.b}", VJ.str(item.data, "owner"))
        assertEquals(before.ver + 1, item.ver)
        assertEquals(VJ.str(before.data, "payload"), VJ.str(item.data, "payload")) // payload и origin не меняются
        assertEquals(VJ.str(before.data, "origin"), VJ.str(item.data, "origin"))
        assertFalse("it_sh1" in s.deck(s.a))
        assertTrue("it_sh1" in s.deck(s.b))
        assertTrue("карточек на телефон нет", s.f.issued.isEmpty())
        // у получателя это груз: рабочим он не становится, `loaded` получателя не тронут
        assertFalse("it_sh1" in VJ.list(s.f.store.get("session", s.b)!!.data, "loaded"))
        s.conserved()
    }

    @Test fun receivedItemIsLootForTheReceiverAndLeavesWithTheirOutcome() {
        val s = stand()
        assertTrue(s.give(s.a, "it_dx", GiveTarget.Session(s.b)).ok)
        // B: полученный демон — груз, не в `moves` оставить нельзя, при clean идёт на телефон
        val moves = listOf(Move("it_dB2", MoveTo.PHONE), Move("it_dx", MoveTo.PHONE))
        val done = s.f.ops.finishRun(s.f.world, "finish:${s.b}", s.b, "clean", "node_07", false, moves)
        assertTrue(done.body.toString(), done.ok)
        assertEquals("outbox:${s.f.keyB}", s.f.owner("it_dx"))
        // A закрывает забег без него; в moves A предмет уже не упомянуть
        val miss = s.f.ops.finishRun(
            s.f.world, "finish:${s.a}:x", s.a, "clean", "node_07", false,
            listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE), Move("it_sh2", MoveTo.PHONE), Move("it_dx", MoveTo.PHONE)),
        )
        assertEquals("wrong_owner", miss.code)
        val a = s.f.ops.finishRun(
            s.f.world, "finish:${s.a}", s.a, "clean", "node_07", false,
            listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE), Move("it_sh2", MoveTo.PHONE)),
        )
        assertTrue(a.body.toString(), a.ok)
        s.conserved()
    }

    @Test fun receivedItemStaysInTheNodeWhenReceiverIsThrownOut() {
        val s = stand()
        assertTrue(s.give(s.a, "it_sh1", GiveTarget.Session(s.b)).ok)
        val moves = listOf(Move("it_dB2", MoveTo.PHONE), Move("it_sh1", MoveTo.NODE))
        assertTrue(s.f.ops.finishRun(s.f.world, "finish:${s.b}", s.b, "soft_ice", "node_07", false, moves).ok)
        assertEquals("node:node_07", s.f.owner("it_sh1"))
        s.conserved()
    }

    @Test fun backAndForthNeedsAFreshRidPerVersion() {
        val s = stand()
        val first = s.give(s.a, "it_sh1", GiveTarget.Session(s.b))
        assertTrue(first.ok)
        val back = s.give(s.b, "it_sh1", GiveTarget.Session(s.a))
        assertTrue(back.body.toString(), back.ok)
        assertFalse("возврат — новая версия, не повтор", back.replayed)
        val again = s.give(s.a, "it_sh1", GiveTarget.Session(s.b))
        assertTrue(again.body.toString(), again.ok)
        assertFalse("A → B → A → B: rid с новой версией, не повтор первого ответа", again.replayed)
        assertEquals("deck:${s.b}", s.f.owner("it_sh1"))
        assertEquals(5L, s.ver("it_sh1")) // ver растёт на каждое изменение: взят в узле и три передачи
        s.conserved()
    }

    // ---------- получатель — телефон ----------

    @Test fun giveToPhoneMakesAnOutboxCardFromTheWorldKey() {
        val s = stand()
        val before = s.f.store.get("item", "it_sh2")!!
        val rid = s.rid(s.a, "it_sh2")
        val r = s.give(s.a, "it_sh2", GiveTarget.Phone(phoneKey))
        assertTrue(r.body.toString(), r.ok)
        val item = s.f.store.get("item", "it_sh2")!!
        assertEquals("outbox:$phoneKey", VJ.str(item.data, "owner"))
        assertEquals("PENDING", VJ.str(item.data, "handover"))
        val tid = "tr_" + VJ.sha256Hex("${s.f.world.namespace}|$rid|it_sh2").take(12)
        assertEquals(tid, VJ.str(item.data, "out_transfer"))
        assertEquals(tid, VJ.str(r.body, "transfer"))
        assertEquals("outbox:$phoneKey", VJ.str(r.body, "to"))
        assertEquals(VJ.str(before.data, "payload"), VJ.str(item.data, "payload"))
        assertFalse("it_sh2" in s.deck(s.a))
        assertEquals(listOf(IssuedTransfer(phoneKey, "it_sh2", 0L, tid)), s.f.issued)
        s.conserved()
    }

    @Test fun giveToPhoneLeavesTheRunForGoodSoNoOutcomeTouchesIt() {
        val s = stand()
        assertTrue(s.give(s.a, "it_dx", GiveTarget.Phone(phoneKey)).ok)
        val moves = listOf(Move("it_dA2", MoveTo.NODE), Move("it_sh1", MoveTo.NODE), Move("it_sh2", MoveTo.NODE))
        assertTrue(s.f.ops.finishRun(s.f.world, "finish:${s.a}", s.a, "black_ice", "node_07", false, moves).ok)
        assertEquals("outbox:$phoneKey", s.f.owner("it_dx")) // флэтлайн отправителя не забрал отданное
        s.conserved()
    }

    // ---------- повтор и идемпотентность ----------

    @Test fun replayReturnsTheSavedAnswerAndMakesNoSecondCard() {
        val s = stand()
        val rid = s.rid(s.a, "it_sh1")
        val ver = s.ver("it_sh1")
        val first = s.give(s.a, "it_sh1", GiveTarget.Phone(phoneKey), rid, ver)
        s.f.issued.clear()
        val second = s.give(s.a, "it_sh1", GiveTarget.Phone(phoneKey), rid, ver)
        assertTrue(second.replayed)
        assertEquals(first.body, second.body)
        assertTrue("вторых карточек нет", s.f.issued.isEmpty())
        assertEquals("outbox:$phoneKey", s.f.owner("it_sh1"))
        s.conserved()
    }

    @Test fun replayToASessionIsAlsoTheSameAnswer() {
        val s = stand()
        val rid = s.rid(s.a, "it_sh1")
        val ver = s.ver("it_sh1")
        val first = s.give(s.a, "it_sh1", GiveTarget.Session(s.b), rid, ver)
        val second = s.give(s.a, "it_sh1", GiveTarget.Session(s.b), rid, ver)
        assertTrue(second.replayed)
        assertEquals(first.body, second.body)
        assertEquals(1, s.deck(s.b).count { it == "it_sh1" })
        s.conserved()
    }

    @Test fun sameRidWithAnotherRecipientIsMismatchAndChangesNothing() {
        val s = stand()
        val rid = s.rid(s.a, "it_sh1")
        val ver = s.ver("it_sh1")
        assertTrue(s.give(s.a, "it_sh1", GiveTarget.Session(s.b), rid, ver).ok)
        assertEquals("rid_mismatch", code { s.give(s.a, "it_sh1", GiveTarget.Phone(phoneKey), rid, ver) })
        assertEquals("deck:${s.b}", s.f.owner("it_sh1"))
        s.conserved()
    }

    @Test fun replayAfterRestartStillWorks() {
        val path = ValueFixture.newPath(tmp.root, "give.db")
        val f = ValueFixture(path)
        val s = Stand(f)
        val rid = s.rid(s.a, "it_sh1")
        val ver = s.ver("it_sh1")
        val first = s.give(s.a, "it_sh1", GiveTarget.Phone(phoneKey), rid, ver)
        f.store.close()
        val store2 = DocStore.open(path)
        val ops2 = ValueOps(store2)
        val again = ops2.giveItem(f.world, rid, s.a, "it_sh1", ver, GiveTarget.Phone(phoneKey))
        assertTrue(again.replayed)
        assertEquals(first.body, again.body)
        store2.close()
    }

    // ---------- что отдавать нельзя ----------

    @Test fun protectedDaemonCannotBeGivenToAnyone() {
        val s = stand()
        for (to in listOf(GiveTarget.Session(s.b), GiveTarget.Phone(phoneKey))) {
            val r = s.give(s.a, "it_dA1", to, rid = "give:${s.a}:it_dA1:${s.ver("it_dA1")}:${to::class.simpleName}")
            assertEquals("protected_item", r.code)
            assertEquals("it_dA1", VJ.str(r.doc!!, "id"))
        }
        assertEquals("deck:${s.a}", s.f.owner("it_dA1"))
        s.conserved()
    }

    @Test fun workingDaemonCannotBeGiven() {
        val s = stand()
        val r = s.give(s.a, "it_dA2", GiveTarget.Session(s.b))
        assertEquals("loaded_item", r.code)
        assertEquals("deck:${s.a}", s.f.owner("it_dA2"))
        // и тот, что принесён с телефона как шард, — тоже рабочий по `loaded`: контракт смотрит на id, а не на вид
        s.conserved()
    }

    @Test fun errorOrderFollowsTheTable() {
        val s = stand()
        // предмет в узле: wrong_owner раньше версии и защиты
        s.f.item("it_far", "node:node_07", "node:node_07", protectedFlag = true)
        assertEquals("wrong_owner", s.give(s.a, "it_far", GiveTarget.Session(s.b), ver = 99).code)
        // свой, но версия устарела: version_conflict раньше protected_item
        assertEquals("version_conflict", s.give(s.a, "it_dA1", GiveTarget.Session(s.b), rid = "x1", ver = 99).code)
        // чужой предмет другой сессии
        assertEquals("wrong_owner", s.give(s.a, "it_dB2", GiveTarget.Session(s.b)).code)
    }

    @Test fun staleVersionIsVersionConflictWithTheItem() {
        val s = stand()
        val r = s.give(s.a, "it_sh1", GiveTarget.Session(s.b), rid = "give:${s.a}:it_sh1:1", ver = 1)
        assertEquals("version_conflict", r.code)
        assertEquals(s.ver("it_sh1"), VJ.lng(r.doc!!, "ver"))
        assertEquals("deck:${s.a}", s.f.owner("it_sh1"))
        // новая версия — новый rid — проходит
        assertTrue(s.give(s.a, "it_sh1", GiveTarget.Session(s.b)).ok)
        s.conserved()
    }

    @Test fun itemNoLongerInTheDeckIsWrongOwnerNotAGift() {
        val s = stand()
        assertTrue(s.give(s.a, "it_sh1", GiveTarget.Session(s.b)).ok)
        val again = s.f.ops.giveItem(s.f.world, "give:${s.a}:it_sh1:${s.ver("it_sh1")}", s.a, "it_sh1", s.ver("it_sh1"), GiveTarget.Phone(phoneKey))
        assertEquals("wrong_owner", again.code)
        assertEquals("deck:${s.b}", s.f.owner("it_sh1"))
        s.conserved()
    }

    // ---------- состояние сессий ----------

    @Test fun recipientNotActiveOrFinishingIsSessionState() {
        val s = stand()
        // состояние получателя: B ещё не нажал курок (pending)
        val sb = s.f.store.get("session", s.b)!!
        s.f.store.put("session", s.b, sb.ver, VJ.with(sb.data, "state" to JsonPrimitive("pending")))
        assertEquals("session_state", s.give(s.a, "it_sh1", GiveTarget.Session(s.b)).code)
        assertEquals("deck:${s.a}", s.f.owner("it_sh1"))
        s.conserved()
    }

    @Test fun senderFinishingOrClosedIsSessionState() {
        val s = stand()
        val sa = s.f.store.get("session", s.a)!!
        val world = JsonObject(mapOf("connected" to JsonPrimitive(true), "finish" to JsonPrimitive("flatline")))
        s.f.store.put("session", s.a, sa.ver, VJ.with(sa.data, "world" to world))
        assertEquals("session_state", s.give(s.a, "it_sh1", GiveTarget.Phone(phoneKey)).code)
        assertEquals("deck:${s.a}", s.f.owner("it_sh1"))
        val sa2 = s.f.store.get("session", s.a)!!
        s.f.store.put("session", s.a, sa2.ver, VJ.with(sa2.data, "world" to JsonObject(emptyMap()), "state" to JsonPrimitive("closed")))
        assertEquals("session_state", s.give(s.a, "it_sh2", GiveTarget.Session(s.b)).code)
    }

    @Test fun recipientFinishingIsSessionState() {
        val s = stand()
        val sb = s.f.store.get("session", s.b)!!
        val world = JsonObject(mapOf("finish" to JsonPrimitive("flatline")))
        s.f.store.put("session", s.b, sb.ver, VJ.with(sb.data, "world" to world))
        assertEquals("session_state", s.give(s.a, "it_sh1", GiveTarget.Session(s.b)).code)
        s.conserved()
    }

    // ---------- запрос неверен ----------

    @Test fun malformedRequestsAreBadRequestAndLeaveNoTrace() {
        val s = stand()
        val ridsBefore = s.f.store.list(ValueOps.RID_TYPE).size
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Session(s.a)) }) // сам себе
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Phone("не ключ")) })
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Phone("")) })
        // некононичный base64 того же ключа: owner `outbox:<ключ>` разошёлся бы с документом runner
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Phone(phoneKey.dropLast(1))) })
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Session(s.b), ver = 0) })
        assertEquals(ridsBefore, s.f.store.list(ValueOps.RID_TYPE).size)
        s.conserved()
    }

    @Test fun ownPhoneIsRefusedByTheContract() {
        val s = stand()
        val own = Ecdsa.encodeKey(Ecdsa.generateKeyPair().public)
        val sa = s.f.store.get("session", s.a)!!
        s.f.store.put("session", s.a, sa.ver, VJ.with(sa.data, "runner" to JsonPrimitive(own)))
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Phone(own)) })
        assertEquals("deck:${s.a}", s.f.owner("it_sh1"))
    }

    @Test fun missingDocumentsAreNotFoundAndNotStored() {
        val s = stand()
        assertEquals("not_found", code { s.give("s_nope", "it_sh1", GiveTarget.Session(s.b), rid = "g1", ver = 1) })
        assertEquals("not_found", code { s.give(s.a, "it_nope", GiveTarget.Session(s.b), rid = "g2", ver = 1) })
        assertEquals("not_found", code { s.give(s.a, "it_sh1", GiveTarget.Session("s_nope"), rid = "g3", ver = s.ver("it_sh1")) })
        assertEquals(0, s.f.store.list(ValueOps.RID_TYPE).count { VJ.str(it.data, "rid") in setOf("g1", "g2", "g3") })
    }

    @Test fun onlyShardsAndDaemonsMayBeGiven() {
        val s = stand()
        val it = s.f.store.get("item", "it_sh1")!!
        s.f.store.put("item", "it_sh1", it.ver, VJ.with(it.data, "kind" to JsonPrimitive("MONEY")))
        assertEquals("bad_request", code { s.give(s.a, "it_sh1", GiveTarget.Session(s.b)) })
    }

    @Test fun bridgeRoleMayNotGive() {
        val s = stand()
        val r = code { s.f.ops.giveItem(Caller(Role.BRIDGE, "b"), "g", s.a, "it_sh1", s.ver("it_sh1"), GiveTarget.Session(s.b)) }
        assertEquals("forbidden", r)
        assertTrue(s.f.ops.giveItem(s.f.master, "g2", s.a, "it_sh1", s.ver("it_sh1"), GiveTarget.Session(s.b)).ok)
    }

    // ---------- сбой посреди операции ----------

    /** Сбой на каждом вызове часов внутри операции: ничего не изменилось, повтор с тем же rid проходит. */
    private fun sweep(to: (Stand) -> GiveTarget) {
        val ref = stand()
        val expected = ref.give(ref.a, "it_sh1", to(ref))
        val n = ref.f.calls
        assertTrue("операция не трогала часы", n > 0)
        for (k in 1..n) {
            val s = stand()
            val before = s.f.snapshot()
            val rid = s.rid(s.a, "it_sh1")
            val ver = s.ver("it_sh1")
            s.f.calls = 0
            s.f.failAt = k
            try { s.give(s.a, "it_sh1", to(s), rid, ver); fail("сбой $k не сработал") } catch (e: IllegalStateException) { assertTrue(e.message!!.contains("сбой")) }
            s.f.failAt = -1
            assertEquals("сбой на вызове $k оставил следы", before, s.f.snapshot())
            s.conserved()
            s.f.issued.clear()
            val r = s.give(s.a, "it_sh1", to(s), rid, ver)
            assertFalse(r.replayed)
            assertEquals(expected.ok, r.ok)
            assertEquals(if (to(s) is GiveTarget.Phone) 1 else 0, s.f.issued.size)
            s.conserved()
        }
    }

    @Test fun faultSweepGiveToSession() = sweep { GiveTarget.Session(it.b) }

    @Test fun faultSweepGiveToPhone() = sweep { GiveTarget.Phone(phoneKey) }

    @Test fun gatewayFailureDoesNotUndoTheGive() {
        val f = ValueFixture(":memory:")
        val ops = ValueOps(f.store, f.clock) { error("M2 упал") }
        val s = Stand(f)
        val r = ops.giveItem(f.world, s.rid(s.a, "it_sh1"), s.a, "it_sh1", s.ver("it_sh1"), GiveTarget.Phone(phoneKey))
        assertTrue(r.ok)
        assertEquals("outbox:$phoneKey", f.owner("it_sh1"))
    }

    // ---------- гонки ----------

    @Test fun twoGivesOfOneItemToDifferentRecipientsLandOnce() {
        repeat(30) {
            val s = stand()
            val ver = s.ver("it_sh1")
            val pool = Executors.newFixedThreadPool(2)
            val start = CountDownLatch(1)
            try {
                val futures = listOf(GiveTarget.Session(s.b), GiveTarget.Phone(phoneKey)).mapIndexed { i, to ->
                    pool.submit<OpResult> { start.await(); s.f.ops.giveItem(s.f.world, "give:${s.a}:it_sh1:$ver:$i", s.a, "it_sh1", ver, to) }
                }
                start.countDown()
                val results = futures.map { it.get(30, TimeUnit.SECONDS) }
                assertEquals(1, results.count { it.ok })
                assertEquals("wrong_owner", results.single { !it.ok }.code)
                s.conserved()
            } finally {
                pool.shutdownNow()
            }
        }
    }

    @Test fun giveAndFinishRaceNeverLoseTheItem() {
        repeat(30) {
            val s = stand()
            val ver = s.ver("it_sh1")
            val pool = Executors.newFixedThreadPool(2)
            val start = CountDownLatch(1)
            try {
                val give = pool.submit<OpResult> { start.await(); s.f.ops.giveItem(s.f.world, "give:${s.a}:it_sh1:$ver", s.a, "it_sh1", ver, GiveTarget.Phone(phoneKey)) }
                val finish = pool.submit<OpResult> {
                    start.await()
                    s.f.ops.finishRun(
                        s.f.world, "finish:${s.a}", s.a, "clean", "node_07", false,
                        listOf(Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE), Move("it_sh2", MoveTo.PHONE), Move("it_dx", MoveTo.PHONE)),
                    )
                }
                start.countDown()
                val g = give.get(30, TimeUnit.SECONDS)
                val fin = finish.get(30, TimeUnit.SECONDS)
                assertEquals("успеть может только один: ${g.body} / ${fin.body}", 1, listOf(g, fin).count { it.ok })
                assertTrue(s.f.owner("it_sh1").startsWith("outbox:"))
                s.conserved()
            } finally {
                pool.shutdownNow()
            }
        }
    }
}
