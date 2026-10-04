package com.megablok10.netrun.bridge

import com.megablok10.rules.ContainerEddies
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** `run.breach` (протокол, 6.6): исход, эдди, хранилища, остывание, сигнал СБ, идемпотентность, отказы. */
class BreachOpsTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun code(r: OpResult): String = r.code ?: "ok"

    /** Код исключения [StoreException] (ошибки, которые не сохраняются по `rid`), "ok" — исключения не было. */
    private fun thrown(block: () -> Any?): String = try { block(); "ok" } catch (e: StoreException) { e.code }
    private fun opened(s: JsonObject): List<JsonObject> = (s["opened"] as JsonArray).map { it as JsonObject }
    private fun strs(o: JsonObject, k: String) = VJ.list(o, k)

    // ---------- успех ----------

    @Test fun successMovesEddiesOpensVaultAndStartsCooldown() {
        val f = BreachFixture()
        val sid = f.enterA()
        val total = f.eddiesTotal()
        val q = f.req(sid, selected = listOf("it_ex", "it_miner"))
        val r = f.breach(sid, q)
        assertTrue(r.body.toString(), r.ok)
        assertEquals("SUCCESS", VJ.str(r.body, "outcome"))
        assertEquals(listOf("EXTRACT_SHARD", "MINER"), strs(r.body, "effects"))
        val expected = f.expectedRoll("breach:$sid:1", Tier.HARD) + ContainerEddies.minerBonus(Tier.HARD)
        assertEquals(expected, VJ.lng(r.body, "eddies"))
        assertEquals(300L - expected, f.nodeEddies())
        val s = f.session(sid)
        assertEquals(expected, VJ.lng(s, "loot_eddies"))
        // экстрактор HARD берёт первое подходящее хранилище-шард: v_sh1 (тир BASE ≤ HARD), владельца Мост не меняет
        val open = opened(s).single()
        assertEquals("v_sh1", VJ.str(open, "item"))
        assertEquals("node:node_07", f.owner("v_sh1"))
        assertEquals(VJ.lng(open, "until"), (r.body["opened"] as JsonArray).map { VJ.lng(it as JsonObject, "until") }.single())
        assertTrue(VJ.lng(open, "until") > f.nowMs)
        assertFalse(VJ.bool(r.body, "exhausted"))
        val breach = s["breach"] as JsonObject
        assertEquals(1L, VJ.lng(breach, "n"))
        assertEquals("SUCCESS", VJ.str(breach, "outcome"))
        assertEquals(1L, VJ.lng(breach, "opened_n"))
        // остывание узла для этого нетраннера: 30 мин
        val cd = (f.runner(f.keyA)["breach_cooldown"] as JsonObject)
        assertEquals(VJ.lng(r.body, "cooldown_until"), VJ.lng(cd, "node_07"))
        assertTrue(VJ.lng(cd, "node_07") - f.nowMs in 1_799_000L..1_800_100L)
        assertEquals(total, f.eddiesTotal())
        assertEquals(emptyList<Violation>(), Auditor(f.store).check())
    }

    @Test fun minerOnlyWhenMatchedNotWhenOnlySelected() {
        val f = BreachFixture()
        val sid = f.enterA()
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex", "it_miner"), matched = listOf("it_ex")))
        assertEquals("PARTIAL", VJ.str(r.body, "outcome"))
        assertEquals(f.expectedRoll("breach:$sid:1", Tier.HARD), VJ.lng(r.body, "eddies"))
    }

    @Test fun eddiesCappedByNodeStock() {
        val f = BreachFixture()
        val sid = f.enterA()
        val nd = f.store.get("node", "node_07")!!
        f.store.put("node", "node_07", nd.ver, VJ.with(nd.data, "eddies" to JsonPrimitive(3L)))
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex", "it_miner")))
        assertEquals(3L, VJ.lng(r.body, "eddies"))
        assertEquals(0L, f.nodeEddies())
        assertEquals(3L, VJ.lng(f.session(sid), "loot_eddies"))
    }

    @Test fun emptyStockGivesNoEddiesButStillOpensVault() {
        val f = BreachFixture()
        val sid = f.enterA()
        val nd = f.store.get("node", "node_07")!!
        f.store.put("node", "node_07", nd.ver, VJ.with(nd.data, "eddies" to JsonPrimitive(0L)))
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex", "it_miner")))
        assertEquals(0L, VJ.lng(r.body, "eddies"))
        assertEquals(1, opened(f.session(sid)).size)
    }

    // ---------- идемпотентность и рестарт ----------

    @Test fun replayReturnsSavedAnswerAndDoesNotDoubleAnything() {
        val f = BreachFixture()
        val sid = f.enterA()
        val q = f.req(sid, selected = listOf("it_ex", "it_miner"))
        val first = f.breach(sid, q)
        val nodeAfter = f.nodeEddies()
        val verSession = f.store.get("session", sid)!!.ver
        val again = f.breach(sid, q)
        assertTrue(again.replayed)
        assertEquals(first.body, again.body)
        assertEquals(nodeAfter, f.nodeEddies())
        assertEquals(verSession, f.store.get("session", sid)!!.ver)
        assertEquals(1, f.secAlerts().size)
        // тот же rid, другие параметры
        assertEquals("rid_mismatch", thrown { f.breach(sid, f.req(sid, selected = listOf("it_ex")), rid = "breach:$sid:1") })
    }

    @Test fun replayAfterBridgeRestartReturnsSameAnswer() {
        val path = tmp.root.resolve("b.db").path
        val f = BreachFixture(path)
        val sid = f.enterA()
        val q = f.req(sid, selected = listOf("it_ex", "it_miner"))
        val first = f.breach(sid, q)
        val sa = f.secAlerts().single()
        f.store.close()
        val store2 = DocStore.open(path)
        val ops2 = ValueOps(store2)
        val again = ops2.runBreach(f.world, "breach:$sid:1", q)
        assertTrue(again.replayed)
        assertEquals(first.body, again.body)
        assertEquals(sa, store2.list("sec_alert").single())  // сигнал пережил рестарт
        store2.close()
    }

    @Test fun crashInsideTransactionLeavesNothingAndRetryCompletes() {
        val ref = BreachFixture()
        val refSid = ref.enterA()
        ref.calls = 0
        ref.breach(refSid, ref.req(refSid, selected = listOf("it_ex", "it_miner")))
        val n = ref.calls
        assertTrue(n > 0)
        for (k in 1..n) {
            val f = BreachFixture()
            val sid = f.enterA()
            val before = f.store.snapshot(setOf("item", "deck", "session", "node", "runner", "sec_alert", "op_rid")).second
            f.calls = 0
            f.failAt = k
            val q = f.req(sid, selected = listOf("it_ex", "it_miner"))
            try {
                f.breach(sid, q)
            } catch (e: IllegalStateException) { /* сбой часов посреди транзакции */ }
            f.failAt = -1
            assertEquals("откат на вызове $k", before, f.store.snapshot(setOf("item", "deck", "session", "node", "runner", "sec_alert", "op_rid")).second)
            val r = f.breach(sid, q)
            assertTrue(r.body.toString(), r.ok)
            assertFalse(r.replayed)
            assertEquals(1, f.secAlerts().size)
            assertEquals(300L, f.eddiesTotal())
        }
    }

    @Test fun eddiesAreDeterministicFromRid() {
        val a = BreachFixture()
        val b = BreachFixture()
        val sa = a.enterA()
        val sb = b.enterA()
        assertEquals(sa, sb)
        val ra = a.breach(sa, a.req(sa, selected = listOf("it_ex", "it_miner")))
        val rb = b.breach(sb, b.req(sb, selected = listOf("it_ex", "it_miner")))
        assertEquals(VJ.lng(ra.body, "eddies"), VJ.lng(rb.body, "eddies"))
    }

    // ---------- хранилища ----------

    @Test fun exhaustedWhenNoVaultFits() {
        val f = BreachFixture()
        val sid = f.enterA()
        // у экстрактора HARD нет подходящего хранилища: только шард тира NIGHTMARE
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex"), vaults = listOf("v_sh3")))
        assertTrue(VJ.bool(r.body, "exhausted"))
        assertEquals(0, opened(f.session(sid)).size)
        // остывание и эдди при этом есть: взлом был успешным
        assertTrue(VJ.lng(r.body, "cooldown_until") > 0)
        assertTrue(VJ.lng(r.body, "eddies") > 0)
    }

    @Test fun emptyVaultListIsExhaustedOnlyWithExtractor() {
        val f = BreachFixture()
        val sid = f.enterA()
        val r = f.breach(sid, f.req(sid, selected = listOf("it_miner"), vaults = emptyList()))
        assertFalse(VJ.bool(r.body, "exhausted"))
        val sid2 = f.enterB()
        val r2 = f.breach(sid2, f.req(sid2, selected = listOf("it_b1"), vaults = emptyList()))
        assertTrue(VJ.bool(r2.body, "exhausted"))
    }

    @Test fun extractShardTakesShardsNotDaemonsAndExtractDaemonTheOpposite() {
        val f = BreachFixture()
        val sid = f.enterA()
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex", "it_exd"), vaults = listOf("v_dm1", "v_sh1")))
        assertEquals(listOf("v_sh1", "v_dm1"), opened(f.session(sid)).map { VJ.str(it, "item") })  // в порядке selected
        assertFalse(VJ.bool(r.body, "exhausted"))
    }

    @Test fun twoExtractorsDoNotPickTheSameVault() {
        val f = BreachFixture()
        val sid = f.enterA()
        // шард один: первому экстрактору (SHARD) достаётся он, второму (DAEMON) нечего
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex", "it_exd"), vaults = listOf("v_sh1")))
        assertEquals(1, opened(f.session(sid)).size)
        assertTrue(VJ.bool(r.body, "exhausted"))
    }

    @Test fun vaultAlreadyOpenedBySomeoneElseIsSkipped() {
        val f = BreachFixture()
        val a = f.enterA()
        val b = f.enterB()
        f.breach(a, f.req(a, selected = listOf("it_ex")))              // A открыл v_sh1
        val r = f.breach(b, f.req(b, selected = listOf("it_b1")))       // B: v_sh1 занят, берёт v_sh2
        assertEquals("v_sh2", VJ.str(opened(f.session(b)).single(), "item"))
        assertFalse(VJ.bool(r.body, "exhausted"))
    }

    @Test fun vaultThatIsNotInTheNodeAnymoreIsSkippedWithoutError() {
        val f = BreachFixture()
        val a = f.enterA()
        val r = f.breach(a, f.req(a, selected = listOf("it_ex"), vaults = listOf("v_nope", "v_sh2")))
        assertTrue(r.body.toString(), r.ok)
        assertEquals("v_sh2", VJ.str(opened(f.session(a)).single(), "item"))
    }

    @Test fun expiredOpeningsAreDroppedOnNextWrite() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, selected = listOf("it_ex"), openS = 1))
        f.advance(1_900_000)  // остывание (30 мин) прошло, окно хранилища давно закрылось
        f.breach(a, f.req(a, n = 2, selected = listOf("it_ex"), vaults = listOf("v_sh2")))
        assertEquals(listOf("v_sh2"), opened(f.session(a)).map { VJ.str(it, "item") })
    }

    // ---------- FAIL, сигнал СБ ----------

    @Test fun failOnBaseGivesNoSignalNoEddiesNoCooldown() {
        val f = BreachFixture()
        val sid = f.enterA()
        val total = f.eddiesTotal()
        val r = f.breach(sid, f.req(sid, tier = "BASE", selected = listOf("it_ex"), matched = emptyList()))
        assertEquals("FAIL", VJ.str(r.body, "outcome"))
        assertEquals(0L, VJ.lng(r.body, "eddies"))
        assertEquals(0L, VJ.lng(r.body, "cooldown_until"))
        assertEquals(JsonNull, r.body["alert"])
        assertTrue(f.secAlerts().isEmpty())
        assertNull(f.runner(f.keyA)["breach_cooldown"])
        assertEquals(0, opened(f.session(sid)).size)
        assertEquals(1L, VJ.lng(f.session(sid)["breach"] as JsonObject, "n"))  // попытка записана
        assertEquals(total, f.eddiesTotal())
    }

    @Test fun failOnHardStillSignalsButNoRewardAndNoCooldown() {
        val f = BreachFixture()
        val sid = f.enterA()
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex"), matched = emptyList()))
        assertEquals("FAIL", VJ.str(r.body, "outcome"))
        assertTrue(r.body["alert"] is JsonObject)
        assertEquals(1, f.secAlerts().size)
        assertEquals(0L, VJ.lng(r.body, "cooldown_until"))
        assertNull(f.runner(f.keyA)["breach_cooldown"])
        assertEquals(300L, f.nodeEddies())
        // после FAIL можно играть сразу: остывания нет
        val r2 = f.breach(sid, f.req(sid, n = 2, selected = listOf("it_ex")))
        assertTrue(r2.ok)
    }

    @Test fun blackoutActiveOrMatchedSuppressesSignal() {
        val f = BreachFixture()
        val a = f.enterA()
        val r = f.breach(a, f.req(a, selected = listOf("it_ex"), active = listOf("BLACKOUT")))
        assertEquals(JsonNull, r.body["alert"])
        assertTrue(f.secAlerts().isEmpty())
        assertEquals(listOf("EXTRACT_SHARD", "BLACKOUT"), strs(r.body, "effects"))
        val f2 = BreachFixture()
        val a2 = f2.enterA()
        val r2 = f2.breach(a2, f2.req(a2, selected = listOf("it_ex", "it_black")))
        assertEquals(JsonNull, r2.body["alert"])
        assertTrue(f2.secAlerts().isEmpty())
    }

    @Test fun ghostHidesCallsignAndWithoutItHardRevealsIt() {
        val f = BreachFixture()
        val a = f.enterA()
        val plain = f.breach(a, f.req(a, selected = listOf("it_ex")))
        val doc = f.secAlerts().single().data
        assertEquals(f.keyA, VJ.str(doc, "callsign"))
        assertEquals(JsonPrimitive(true), (plain.body["alert"] as JsonObject)["callsign"])
        assertEquals("Арасака", VJ.str(doc, "faction"))
        assertEquals("Склад Арасаки", VJ.str(doc, "title"))
        assertEquals(2L, VJ.lng(doc, "tier"))
        assertEquals(JsonNull, doc["precise_at"])
        assertEquals("pending", VJ.str(doc, "state"))

        val g = BreachFixture()
        val ga = g.enterA()
        val r = g.breach(ga, g.req(ga, selected = listOf("it_ex", "it_ghost")))
        assertEquals(JsonNull, g.secAlerts().single().data["callsign"])
        assertEquals(JsonPrimitive(false), (r.body["alert"] as JsonObject)["callsign"])
    }

    @Test fun timeskewAddsTenMinutesToTheTwoMinuteDelay() {
        val f = BreachFixture()
        val a = f.enterA()
        val r = f.breach(a, f.req(a, selected = listOf("it_ex", "it_time")))
        val doc = f.secAlerts().single().data
        val decision = VJ.lng(doc, "ttl_at") - 30 * 60_000L
        assertEquals(decision + 12 * 60_000L, VJ.lng(doc, "send_at"))
        assertEquals(VJ.lng(doc, "send_at"), VJ.lng(r.body["alert"] as JsonObject, "send_at"))
        val g = BreachFixture()
        val ga = g.enterA()
        g.breach(ga, g.req(ga, selected = listOf("it_ex")))
        val d2 = g.secAlerts().single().data
        assertEquals(VJ.lng(d2, "ttl_at") - 30 * 60_000L + 2 * 60_000L, VJ.lng(d2, "send_at"))
    }

    @Test fun nightmareIsImmediateWithPreciseTime() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, tier = "NIGHTMARE", selected = listOf("it_ex")))
        val d = f.secAlerts().single().data
        assertEquals(VJ.lng(d, "ttl_at") - 30 * 60_000L, VJ.lng(d, "send_at"))
        assertEquals(VJ.lng(d, "send_at"), VJ.lng(d, "precise_at"))
    }

    @Test fun ownFactionNodeGivesNoSignal() {
        val f = BreachFixture()
        val a = f.enterA()
        val rd = f.store.get("runner", ValueOps.runnerDocId(f.keyA))!!
        f.store.put("runner", rd.id, rd.ver, VJ.with(rd.data, "faction" to JsonPrimitive("Арасака")))
        val r = f.breach(a, f.req(a, selected = listOf("it_ex")))
        assertEquals(JsonNull, r.body["alert"])
        assertTrue(f.secAlerts().isEmpty())
    }

    // ---------- остывание ----------

    @Test fun cooldownRefusesSecondBreachAndLeavesNothingElseChanged() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, selected = listOf("it_ex")))
        val snap = f.store.snapshot(setOf("item", "deck", "session", "node", "runner", "sec_alert")).second
        val r = f.breach(a, f.req(a, n = 2, selected = listOf("it_ex")))
        assertEquals("cooldown", code(r))
        assertEquals(f.runner(f.keyA), r.doc!!["data"])
        assertEquals(snap, f.store.snapshot(setOf("item", "deck", "session", "node", "runner", "sec_alert")).second)
        // сохраняется по rid: повтор — тот же отказ
        assertEquals("cooldown", code(f.breach(a, f.req(a, n = 2, selected = listOf("it_ex")))))
        // другой нетраннер этого же узла не остывает
        val b = f.enterB()
        assertTrue(f.breach(b, f.req(b, selected = listOf("it_b1"))).ok)
    }

    @Test fun cooldownEndsAfterThirtyMinutesAndExpiredKeysAreCleaned() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, selected = listOf("it_ex")))
        val rd = f.store.get("runner", ValueOps.runnerDocId(f.keyA))!!
        val old = VJ.with(rd.data, "breach_cooldown" to JsonObject((rd.data["breach_cooldown"] as JsonObject) + ("node_99" to JsonPrimitive(5L))))
        f.store.put("runner", rd.id, rd.ver, old)
        f.advance(30 * 60_000L + 10)
        val r = f.breach(a, f.req(a, n = 2, selected = listOf("it_ex"), vaults = listOf("v_sh2")))
        assertTrue(r.body.toString(), r.ok)
        val cd = f.runner(f.keyA)["breach_cooldown"] as JsonObject
        assertEquals(setOf("node_07"), cd.keys)
    }

    @Test fun masterCanClearCooldownByPutting() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, selected = listOf("it_ex")))
        val rd = f.store.get("runner", ValueOps.runnerDocId(f.keyA))!!
        f.store.put("runner", rd.id, rd.ver, VJ.with(rd.data, "breach_cooldown" to JsonObject(emptyMap())))
        assertTrue(f.breach(a, f.req(a, n = 2, selected = listOf("it_ex"), vaults = listOf("v_sh2"))).ok)
    }

    // ---------- claimed ----------

    @Test fun takeFromOtherSessionsOpenVaultIsClaimed() {
        val f = BreachFixture()
        val a = f.enterA()
        val b = f.enterB()
        f.breach(a, f.req(a, selected = listOf("it_ex"), openS = 60))
        val denied = f.ops.takeFromNode(f.world, "take:$b:v_sh1", b, "node_07", "v_sh1")
        assertEquals("claimed", code(denied))
        assertEquals("v_sh1", denied.doc!!["id"]!!.let { (it as JsonPrimitive).content })
        assertEquals("node:node_07", f.owner("v_sh1"))
        // открывший берёт без помех
        val mine = f.ops.takeFromNode(f.world, "take:$a:v_sh1", a, "node_07", "v_sh1")
        assertTrue(mine.body.toString(), mine.ok)
        assertEquals("deck:$a", f.owner("v_sh1"))
        // чужой, не открытый ничьим взломом предмет — берётся, как раньше
        assertTrue(f.ops.takeFromNode(f.world, "take:$b:v_sh3", b, "node_07", "v_sh3").ok)
    }

    @Test fun claimExpiresWithTheOpeningWindowAndWithTheOwnerSession() {
        val f = BreachFixture()
        val a = f.enterA()
        val b = f.enterB()
        f.breach(a, f.req(a, selected = listOf("it_ex"), openS = 1))
        f.advance(1_500)
        assertTrue(f.ops.takeFromNode(f.world, "take:$b:v_sh1", b, "node_07", "v_sh1").ok)
        // закрытая сессия открывшего не удерживает хранилище
        val f2 = BreachFixture()
        val a2 = f2.enterA()
        val b2 = f2.enterB()
        f2.breach(a2, f2.req(a2, selected = listOf("it_ex"), openS = 600))
        val s = f2.store.get("session", a2)!!
        f2.store.put("session", a2, s.ver, VJ.with(s.data, "state" to JsonPrimitive("closed")))
        assertTrue(f2.ops.takeFromNode(f2.world, "take:$b2:v_sh1", b2, "node_07", "v_sh1").ok)
    }

    // ---------- добыча master:* ----------

    @Test fun masterStockedLootCannotGoToPhoneOnSoftIce() {
        val f = BreachFixture()
        val a = f.enterA()
        f.vaultItem("v_master", "SHARD", Tier.BASE, origin = "master:master-anna")
        assertTrue(f.ops.takeFromNode(f.world, "take:$a:v_master", a, "node_07", "v_master").ok)
        val toPhone = f.daemonsA.map { Move(it.first, MoveTo.PHONE) }
        // выброс: добыча (и от мастера тоже) остаётся в узле, на телефон не уходит
        assertEquals("bad_request", thrown { f.ops.finishRun(f.world, "finish:$a", a, "soft_ice", "node_07", false, toPhone + Move("v_master", MoveTo.PHONE)) })
    }

    @Test fun masterStockedLootStaysInNodeOnSoftIceAndGoesToPhoneOnClean() {
        val f = BreachFixture()
        val a = f.enterA()
        f.vaultItem("v_master", "SHARD", Tier.BASE, origin = "master:master-anna")
        f.ops.takeFromNode(f.world, "take:$a:v_master", a, "node_07", "v_master")
        val others = f.daemonsA.map { it.first }.map { Move(it, MoveTo.PHONE) }
        val r = f.ops.finishRun(f.world, "finish:$a", a, "soft_ice", "node_07", false, others + Move("v_master", MoveTo.NODE))
        assertTrue(r.body.toString(), r.ok)
        assertEquals("node:node_07", f.owner("v_master"))

        val g = BreachFixture()
        val ga = g.enterA()
        g.vaultItem("v_master", "SHARD", Tier.BASE, origin = "master:master-anna")
        g.ops.takeFromNode(g.world, "take:$ga:v_master", ga, "node_07", "v_master")
        val rc = g.ops.finishRun(g.world, "finish:$ga", ga, "clean", "node_07", false, g.daemonsA.map { Move(it.first, MoveTo.PHONE) } + Move("v_master", MoveTo.PHONE))
        assertTrue(rc.body.toString(), rc.ok)
        assertEquals("outbox:${g.keyA}", g.owner("v_master"))
        assertEquals(emptyList<Violation>(), Auditor(g.store).check())
    }

    @Test fun nodeOriginLootRuleIsUnchanged() {
        val f = BreachFixture()
        val a = f.enterA()
        f.ops.takeFromNode(f.world, "take:$a:v_sh1", a, "node_07", "v_sh1")
        val toPhone = f.daemonsA.map { Move(it.first, MoveTo.PHONE) }
        assertEquals("bad_request", thrown { f.ops.finishRun(f.world, "finish:$a", a, "emergency", "node_07", false, toPhone + Move("v_sh1", MoveTo.PHONE)) })
        assertTrue(f.ops.finishRun(f.world, "finish:$a", a, "emergency", "node_07", false, toPhone + Move("v_sh1", MoveTo.NODE)).ok)
    }

    // ---------- отказы ----------

    private fun badRequest(block: () -> OpResult): Boolean = thrown(block) == "bad_request"

    @Test fun malformedRequestsAreBadRequestAndNotSaved() {
        val f = BreachFixture()
        val a = f.enterA()
        val ok = f.req(a, selected = listOf("it_ex"))
        val cases = listOf(
            ok.copy(n = 0), ok.copy(tier = "EASY"), ok.copy(openS = 0), ok.copy(openS = 601), ok.copy(selected = emptyList(), matched = emptyList()),
            ok.copy(selected = listOf("it_ex", "it_ex")), ok.copy(matched = listOf("it_miner")), ok.copy(active = listOf("MINER")),
            ok.copy(active = listOf("GHOST", "GHOST")), ok.copy(vaults = listOf("v_sh1", "v_sh1")),
            ok.copy(selected = listOf("v_sh1"), matched = emptyList()),                  // не демон, лежит в узле
            ok.copy(selected = listOf("it_b1"), matched = emptyList()),                    // демон чужой сессии
            ok.copy(selected = listOf("nope"), matched = emptyList()),
            ok.copy(node = "node_99"),
        )
        for ((i, q) in cases.withIndex()) {
            val expected = if (q.node == "node_99") "not_found" else "bad_request"
            val code = try { f.breach(a, q, rid = "bad:$i"); "ok" } catch (e: StoreException) { e.code }
            assertEquals("случай $i", expected, code)
        }
        assertTrue(f.store.list("op_rid").none { VJ.str(it.data, "rid")?.startsWith("bad:") == true })
        assertEquals(300L, f.nodeEddies())
        assertTrue(f.breach(a, ok).ok)  // ни один отказ не занял rid и не сдвинул n
    }

    @Test fun chainsLongerThanRamAreBadRequest() {
        val f = BreachFixture()
        val a = f.enterA()
        val s = f.store.get("session", a)!!
        f.store.put("session", a, s.ver, VJ.with(s.data, "ram" to JsonPrimitive(3L)))
        assertTrue(badRequest { f.breach(a, f.req(a, selected = listOf("it_ex", "it_exd"), matched = emptyList())) })
        assertTrue(f.breach(a, f.req(a, selected = listOf("it_ex"))).ok)
    }

    @Test fun submitDeckWritesRamAndLoadedAndCargoIsNotAWorkingDaemon() {
        val f = BreachFixture()
        val a = f.enterA()
        val s = f.session(a)
        assertEquals(12L, VJ.lng(s, "ram"))
        assertEquals(f.daemonsA.map { it.first }, strs(s, "loaded"))
        // демон из узла (груз) во взлом выбрать нельзя, даже лёжа в деке
        f.vaultItem("v_cargo_d", "DAEMON", Tier.BASE)
        assertTrue(f.ops.takeFromNode(f.world, "take:$a:v_cargo_d", a, "node_07", "v_cargo_d").ok)
        assertTrue(badRequest { f.breach(a, f.req(a, selected = listOf("v_cargo_d"), matched = emptyList())) })
    }

    @Test fun sessionStateErrorsAreSavedByRid() {
        val f = BreachFixture()
        val a = f.enterA()
        // идёт исход
        f.setWorld(a, "finish" to JsonPrimitive("flatline"))
        assertEquals("session_state", code(f.breach(a, f.req(a, selected = listOf("it_ex")))))
        f.setWorld(a, "finish" to JsonPrimitive(""))
        // сессия не активна
        val b = f.enter(f.keyB, "t04", "it_b1", "it_b2")
        val sb = f.store.get("session", b)!!
        f.store.put("session", b, sb.ver, VJ.with(sb.data, "state" to JsonPrimitive("closed")))
        assertEquals("session_state", code(f.breach(b, f.req(b, selected = listOf("it_b1")))))
    }

    @Test fun staleAttemptNumberIsRefused() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, n = 3, selected = listOf("it_ex"), matched = emptyList()))
        assertEquals("session_state", code(f.breach(a, f.req(a, n = 3, selected = listOf("it_ex")), rid = "breach:$a:3b")))
        assertEquals("session_state", code(f.breach(a, f.req(a, n = 2, selected = listOf("it_ex")))))
        assertTrue(f.breach(a, f.req(a, n = 4, selected = listOf("it_ex"))).ok)
    }

    @Test fun tutorialNodeIsRefused() {
        val f = BreachFixture()
        val rd = f.store.get("runner", ValueOps.runnerDocId(f.keyA))!!
        f.store.put("runner", rd.id, rd.ver, VJ.with(rd.data, "tutorial_done" to JsonPrimitive(false)))
        val a = f.enterA()  // забег учебный: сессия в node_00
        assertEquals("node_00", VJ.str(f.session(a), "node"))
        assertEquals("session_state", code(f.breach(a, f.req(a, node = "node_00", selected = listOf("it_ex")))))
    }

    @Test fun wrongCurrentNodeIsBadRequestAndWorldNodeWins() {
        val f = BreachFixture()
        val a = f.enterA()
        f.store.put("node", "node_08", 0, VJ.obj("tier" to VJ.p("HARD"), "eddies" to VJ.p(40L), "lockdown_until" to VJ.p(0L)))
        assertTrue(badRequest { f.breach(a, f.req(a, node = "node_08", selected = listOf("it_ex"))) })
        f.setWorld(a, "node" to JsonPrimitive("node_08"))
        val r = f.breach(a, f.req(a, node = "node_08", selected = listOf("it_ex"), vaults = emptyList()))
        assertTrue(r.body.toString(), r.ok)
        assertEquals(setOf("node_08"), (f.runner(f.keyA)["breach_cooldown"] as JsonObject).keys)
        assertEquals(300L, f.nodeEddies())
    }

    @Test fun cargoVaultOwnedByAnotherNodeOrDeckIsIgnored() {
        val f = BreachFixture()
        val a = f.enterA()
        f.vaultItem("v_elsewhere", "SHARD", Tier.BASE, owner = "node:node_00")
        val r = f.breach(a, f.req(a, selected = listOf("it_ex"), vaults = listOf("v_elsewhere", "it_miner")))
        assertTrue(VJ.bool(r.body, "exhausted"))
        assertEquals(0, opened(f.session(a)).size)
    }

    @Test fun bridgeRoleIsForbidden() {
        val f = BreachFixture()
        val a = f.enterA()
        assertEquals("forbidden", thrown { f.breach(a, f.req(a, selected = listOf("it_ex")), caller = Caller(Role.BRIDGE, "b")) })
    }

    @Test fun secAlertIsNotWritableByPutButMasterCanDeleteIt() {
        val f = BreachFixture()
        val a = f.enterA()
        f.breach(a, f.req(a, selected = listOf("it_ex")))
        val d = f.secAlerts().single()
        val e = runCatching { WriteGuard.checkValues("sec_alert", d, VJ.with(d.data, "state" to JsonPrimitive("sent"))) }.exceptionOrNull() as StoreException
        assertEquals("value_field", e.code)
        WriteGuard.checkValues("sec_alert", d, null)  // удаление разрешено
    }
}
