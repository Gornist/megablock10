package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.SyncConfig
import com.megablok10.kit.time.Clock
import com.megablok10.netrun.bridge.BridgeApp
import com.megablok10.netrun.bridge.Caller
import com.megablok10.netrun.bridge.CommitHook
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.Move
import com.megablok10.netrun.bridge.MoveTo
import com.megablok10.netrun.bridge.Role
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueFixture
import com.megablok10.netrun.bridge.ValueOps
import com.megablok10.netrun.bridge.collector.FakeCollector.Companion.str
import com.megablok10.netrun.bridge.parseLaunch
import com.megablok10.netrun.bridge.phone.WorldKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.atomic.AtomicLong

/**
 * Мост целиком по быстрым событиям: операции с ценностями → транзакция хранилища → хук коммита → [WorldEventSender] → настоящий HTTP до
 * [FakeCollector]. Записи мира идут рядом (`/api/changes`), события — отдельно и мимо очереди.
 */
class WorldEventsBridgeTest {
    @get:Rule val tmp = TemporaryFolder()
    private val collector = FakeCollector()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val log = RecordingLog()
    private val key = WorldKey.generate()

    /** Разница между «сейчас» Моста и временем часов стенда документов (у `ValueFixture` оно начинается с тысячи миллисекунд). */
    private val skew = AtomicLong(0)

    private val fastSync = SyncConfig(backoffMs = longArrayOf(20), idlePollMs = 30, noEndpointPollMs = 30, jitter = 0.0)
    private val fastEvents = WorldEventConfig(retryDelayMs = 40, notCapableTtlMs = 0, warnEveryMs = 600_000)

    @After fun tearDown() {
        scope.cancel()
        collector.close()
    }

    /** Часы Моста и коллектора идут по часам стенда документов: срок жизни события считается от времени документа, как в бою. */
    private fun clockOf(f: ValueFixture) = Clock { f.nowMs + skew.get() }

    private fun sync(f: ValueFixture, endpoint: CollectorEndpoint? = CollectorEndpoint(collector.url, null)): WorldSync {
        collector.eventClock = { f.nowMs + skew.get() }
        return WorldSync(f.store, key, endpoint, scope, clock = clockOf(f), config = fastSync, log = log, eventConfig = fastEvents)
    }

    private fun await(what: String, timeoutMs: Long = 10_000, cond: () -> Boolean) {
        val until = System.currentTimeMillis() + timeoutMs
        while (!cond()) {
            check(System.currentTimeMillis() < until) { "не дождались: $what (журнал: ${log.all.takeLast(8)})" }
            Thread.sleep(POLL_MS)
        }
    }

    private fun ValueFixture.world(sid: String, vararg fields: Pair<String, Any>) {
        val s = store.get("session", sid)!!
        val old = (s.data["world"] as? JsonObject) ?: JsonObject(emptyMap())
        val extra = fields.associate { (k, v) -> k to if (v is Boolean) JsonPrimitive(v) else JsonPrimitive(v as Number) }
        store.put("session", sid, s.ver, VJ.with(s.data, "world" to JsonObject(old + extra)))
    }

    /**
     * Забег игрока A (вход, trace TRACE, охота, выброс Soft ICE с локдауном узла), забег игрока B с флэтлайном и тревога аудитора.
     * Возвращает, какие быстрые события ждём, по порядку.
     */
    private fun playScenario(f: ValueFixture): List<String> {
        val a = f.enterActive(f.keyA, "t03", "it_dA1", "it_dA2")
        f.world(a, "trace_level" to 2, "trace" to 60)
        f.world(a, "hunt" to true)
        f.ops.finishRun(f.world, "finish:$a", a, "soft_ice", "node_07", false, listOf(Move("it_dA2", MoveTo.PHONE))).also { assertTrue(it.body.toString(), it.ok) }
        f.store.put("node", "node_07", f.store.get("node", "node_07")!!.ver, VJ.with(f.store.get("node", "node_07")!!.data, "lockdown_until" to VJ.p(0L))) // мастер открыл узел
        val b = f.enterActive(f.keyB, "t04", "it_dB1", "it_dB2")
        f.ops.finishRun(f.world, "finish:$b", b, "black_ice", "node_07", false, listOf(Move("it_dB2", MoveTo.NODE))).also { assertTrue(it.body.toString(), it.ok) }
        f.store.put("alert", "al_a_1", 0, f.obj("kind" to "auditor_item_owner", "msg" to "it_x: владелец", "items" to "x"))
        return listOf("run.enter", "trace.level", "ice.hunt", "run.exit", "lockdown", "run.enter", "flatline", "run.exit", "alert.master")
    }

    // ---------- события доходят ----------

    @Test fun everyKindArrivesOverHttpWithItsTerminalAndNodeAndRecordsStillFlow() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        val expected = playScenario(f)
        w.start()
        await("все события у коллектора") { collector.events.size == expected.size }
        assertEquals(expected.sorted(), collector.eventKinds().sorted())
        assertEquals(FastKinds.ALL.toSet(), collector.eventKinds().toSet()) // семь видов контракта, ни одного лишнего
        assertEquals(0, collector.eventsInvalid.get())
        assertEquals(0, collector.eventsDuplicate.get())
        assertEquals(collector.events.size, collector.events.map { it.str("id") }.toSet().size)
        val byKind = collector.events.groupBy { it.str("kind") }
        assertEquals("TRACE", byKind.getValue("trace.level").single().str("level"))
        assertEquals(listOf("node_07", "t03"), listOf("node", "terminal").map { byKind.getValue("ice.hunt").single().str(it) })
        assertEquals(listOf("node_07", "t04"), listOf("node", "terminal").map { byKind.getValue("flatline").single().str(it) })
        assertEquals(null, byKind.getValue("alert.master").single().str("terminal"))
        // записи мира идут своим путём и не затронуты: в хранилище коллектора только `w:`-записи, события в них не попали
        await("записи у коллектора и пустая очередь") { collector.stored.isNotEmpty() && runBlocking { w.queue.count() } == 0 }
        assertTrue(collector.stored.keys.toString(), collector.stored.keys.all { it.startsWith("w:") })
        assertTrue(collector.events.none { it.str("id")!! in collector.stored.keys })
        assertEquals(setOf("NET_ENTER", "NET_EXIT", "NET_FLATLINE", "NET_ITEM_OWNER", "NET_ALERT"), collector.stored.values.map { it.str("reason")!! }.toSet())
    }

    @Test fun eventsNeverGoIntoTheRecordQueue() {
        val f = ValueFixture(":memory:")
        val w = sync(f, endpoint = null) // коллектора нет: записи копятся, события не выводятся вовсе
        playScenario(f)
        val records = runBlocking { w.queue.nextBatch(1000) }
        assertTrue(records.toString(), records.isNotEmpty() && records.all { it.id.startsWith("w:") && it.field.startsWith("net.") })
        assertEquals(0, w.eventsQueued)
        assertEquals(0, collector.eventPosts.get())
        assertEquals(0, collector.capabilityGets.get())
    }

    @Test fun eventsAreOffTogetherWithTheCollectorAndNothingIsHeldInMemory() {
        val f = ValueFixture(":memory:")
        val w = WorldSync(f.store, key, null, scope, clock = clockOf(f), config = fastSync, log = log, eventConfig = fastEvents)
        w.start()
        playScenario(f)
        assertEquals(0, w.eventsQueued)
    }

    // ---------- не мешает транзакциям ----------

    @Test fun hungCollectorDoesNotSlowDownTransactions() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        collector.eventDelayMs = 3_000
        w.start()
        val t0 = System.nanoTime()
        val expected = playScenario(f) // девять событий; коллектор ответит на первый запрос только через 3 с
        val ms = (System.nanoTime() - t0) / NS_IN_MS
        assertTrue("забег с событиями занял $ms мс при зависшем коллекторе", ms < 1_500)
        assertEquals(0, collector.events.size) // к этому моменту коллектор ничего не принял: операции не ждали сеть
        assertTrue(w.eventsQueued + collector.eventPosts.get() > 0)
        f.assertConserved() // и ценности целы
        collector.eventDelayMs = 0
        await("события дошли после ответа", 15_000) { collector.events.isNotEmpty() }
        assertTrue(expected.isNotEmpty())
    }

    @Test fun unreachableCollectorKeepsBridgeWorkingAndHoldsNothing() {
        val f = ValueFixture(":memory:")
        val dead = "http://127.0.0.1:${java.net.ServerSocket(0).use { it.localPort }}"
        val w = sync(f, CollectorEndpoint(dead, "Sekret-QQMARKER"))
        w.start()
        playScenario(f) // все операции проходят, хотя коллектора нет
        f.assertConserved()
        await("очередь событий пуста") { w.eventsQueued == 0 && log.has("world_events.unreachable") }
        assertTrue(runBlocking { w.queue.count() } > 0) // записи мира копятся до появления коллектора
        assertTrue(log.all.toString(), log.all.none { "QQMARKER" in it })
        assertTrue(log.all.any { it.startsWith("W/WorldEvents world_events.unreachable ") })
    }

    @Test fun rolledBackTransactionMakesNoEvents() {
        val f = ValueFixture(":memory:")
        val w = sync(f) // отправка не запущена: что вывел хук, то и лежит в очереди
        val sid = f.ops.submitDeck(f.test, "enter:e1", f.keyA, "Призрак", "t03", listOf("it_dA1", "it_dA2"), "it_dA1").let { f.sessionOf(it) }
        val inner = f.store.commitHook!!
        f.store.commitHook = CommitHook { c, ch, prev ->
            inner.beforeCommit(c, ch, prev)
            error("сбой после вывода событий")
        }
        assertTrue(runCatching { f.activate(sid) }.isFailure)
        assertEquals("pending", VJ.str(f.store.get("session", sid)!!.data, "state"))
        assertEquals(0, w.eventsQueued) // откат стёр и события: площадка не услышит «в Сети» про вход, которого не было
        f.store.commitHook = inner
        f.activate(sid)
        assertEquals(1, w.eventsQueued)
    }

    @Test fun failedDeriveOfFastEventsWarnsAndKeepsTheDocuments() {
        // События — не ценность: сбой их вывода не откатывает документы (как и у записей мира), но виден в журнале предупреждением.
        val f = ValueFixture(":memory:")
        val sent = ArrayList<List<FastEvent>>()
        val recorder = WorldRecorder(WorldRecordQueue(f.store), key, f.store.epoch, log) { sent += it }
        f.store.commitHook = CommitHook { c, changes, _ -> recorder.beforeCommit(c, changes) { error("сбой чтения прежнего документа") } }
        f.store.addListener { recorder.committed {} }
        val session = f.store.put("session", "s_broken", 0, f.obj("state" to "active", "node" to "node_07", "terminal" to "t03"))
        assertEquals(session, f.store.get("session", "s_broken")) // документ зафиксирован
        val warn = log.all.single { "world.fast_derive_failed" in it }
        assertTrue(warn, warn.startsWith("W/WorldRecords ") && "IllegalStateException" in warn)
        assertEquals(emptyList<List<FastEvent>>(), sent) // и не вывелось ничего: ни половины событий
    }

    // ---------- идентификаторы ----------

    @Test fun twoLivesOfTheBaseUnderOneKeyNeverReuseAnEventId() {
        // Сброс файла базы: те же номера транзакций и те же id документов, но эпоха новая (M4b) — коллектор не должен счесть событие дублем.
        val ids = ArrayList<String>()
        repeat(2) { life ->
            val f = ValueFixture(":memory:")
            val w = sync(f)
            f.store.put("session", "s_fixed", 0, f.obj("state" to "pending", "terminal" to "t03", "node" to "node_07", "runner" to f.keyA))
            val s = f.store.get("session", "s_fixed")!!
            f.store.put("session", "s_fixed", s.ver, VJ.with(s.data, "state" to JsonPrimitive("active")))
            w.start()
            await("событие жизни $life") { collector.events.size == life + 1 }
            ids += collector.events.last().str("id")!!
        }
        assertEquals(2, ids.toSet().size)
        assertEquals(0, collector.eventsDuplicate.get())
        assertEquals(ids[0].split(":")[2], ids[1].split(":")[2]) // одно и то же событие, один и тот же номер транзакции...
        assertTrue(ids.toString(), ids[0].split(":")[1] != ids[1].split(":")[1]) // ...и разная эпоха базы
    }

    // ---------- запуск целиком ----------

    @Test fun bridgeAppSendsEventsFromTheLaunchFlagWithTheSecret() {
        collector.requiredSecret = "sekret"
        val db = tmp.root.resolve("app.db").path
        val env = mapOf("NETRUN_KEY_WORLD" to "w", "NETRUN_KEY_MASTER" to "m", "NETRUN_COLLECTOR_SECRET" to "sekret")
        val options = parseLaunch(listOf("--port", "0", "--line-port", "0", "--db", db, "--collector", collector.url + "/"), env)
        BridgeApp(options, fastSync).use { app ->
            app.start()
            val s: DocStore = app.store
            s.put("node", "node_07", 0, VJ.obj("tier" to VJ.p("STANDARD"), "lockdown_until" to VJ.p(0L), "eddies" to VJ.p(10L)))
            s.put("terminal", "t03", 0, VJ.obj("node" to VJ.p("node_07")))
            for (id in listOf("it_a", "it_b")) {
                s.put("item", id, 0, VJ.obj("owner" to VJ.p("inbox:KEY_A"), "kind" to VJ.p("DAEMON"), "payload" to VJ.p("p"), "protected" to VJ.p(false), "origin" to VJ.p("phone:KEY_A")))
            }
            s.put("runner", ValueOps.runnerDocId("KEY_A"), 0, VJ.obj("key" to VJ.p("KEY_A"), "callsign" to VJ.p("KEY_A"), "blocked" to VJ.p(false), "runs" to VJ.p(1L), "tutorial_done" to VJ.p(true)))
            val r = ValueOps(s).submitDeck(Caller(Role.TEST, "t"), "enter:1", "KEY_A", "Призрак", "t03", listOf("it_a", "it_b"), "it_a")
            assertTrue(r.body.toString(), r.ok)
            val sid = VJ.str(r.body, "session")!!
            val doc = s.get("session", sid)!!
            s.put("session", sid, doc.ver, VJ.with(doc.data, "state" to JsonPrimitive("active"))) // курок
            await("run.enter у коллектора") { collector.events.any { it.str("kind") == "run.enter" } }
            val enter = collector.events.single { it.str("kind") == "run.enter" }
            assertEquals(listOf("node_07", "t03", sid), listOf("node", "terminal", "session").map { enter.str(it) })
            assertTrue(collector.eventSecrets.all { it == "sekret" })
            assertEquals(0, collector.eventsExpired.get())
        }
    }

    private companion object {
        const val POLL_MS = 15L
        const val NS_IN_MS = 1_000_000L
    }
}
