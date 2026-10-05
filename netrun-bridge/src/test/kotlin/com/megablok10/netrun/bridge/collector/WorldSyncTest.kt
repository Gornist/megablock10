package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.SyncConfig
import com.megablok10.kit.time.Clock
import com.megablok10.netrun.bridge.BridgeApp
import com.megablok10.netrun.bridge.Caller
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.Move
import com.megablok10.netrun.bridge.MoveTo
import com.megablok10.netrun.bridge.Role
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueFixture
import com.megablok10.netrun.bridge.ValueOps
import com.megablok10.netrun.bridge.collector.FakeCollector.Companion.long
import com.megablok10.netrun.bridge.collector.FakeCollector.Companion.str
import com.megablok10.netrun.bridge.parseLaunch
import com.megablok10.netrun.bridge.phone.WorldKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Мост → коллектор целиком: запись мира → очередь SQLite → `SyncEngine` → HTTP до [FakeCollector]. Коллектор проверяет подпись
 * своим кодом и ведёт себя как настоящий: повтор того же `id` — «принято» без второй записи, незнакомая причина — `rejected`.
 */
class WorldSyncTest {
    @get:Rule val tmp = TemporaryFolder()
    private val collector = FakeCollector()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val scope2 = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val log = RecordingLog()
    private val key = WorldKey.generate()

    /** Паузы в десятки миллисекунд: тест ждёт настоящий HTTP, но не настоящие 30 секунд. */
    private val fast = SyncConfig(backoffMs = longArrayOf(20), idlePollMs = 30, noEndpointPollMs = 30, jitter = 0.0)

    @After fun tearDown() {
        scope.cancel()
        scope2.cancel()
        collector.close()
    }

    private fun endpoint(secret: String? = null) = CollectorEndpoint(collector.url, secret)

    private fun sync(f: ValueFixture, endpoint: CollectorEndpoint? = endpoint()) = WorldSync(f.store, key, endpoint, scope, config = fast, log = log)

    private fun queued(w: WorldSync): Int = runBlocking { w.queue.count() }

    /** Забег с флэтлайном: вход, взятие шарда, исход — пять записей разных видов. */
    private fun playRun(f: ValueFixture): List<String> {
        val r = f.ops.submitDeck(f.test, "enter:e1", f.keyA, "Призрак", "t03", listOf("it_dA1", "it_dA2"), "it_dA1")
        val sid = f.sessionOf(r)
        f.activate(sid)
        f.ops.takeFromNode(f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1")
        f.ops.finishRun(f.world, "finish:$sid", sid, "emergency", "node_07", false, listOf(Move("it_dA2", MoveTo.BURNED), Move("it_sh1", MoveTo.NODE)))
        // в одной транзакции сначала запись сессии, затем предметы по id: it_dA2 (сгорел), it_sh1 (в узел)
        return listOf("NET_ENTER", "NET_ITEM_OWNER", "NET_EXIT", "NET_ITEM_OWNER", "NET_ITEM_OWNER")
    }

    private fun await(what: String, timeoutMs: Long = 10_000, cond: () -> Boolean) {
        val until = System.currentTimeMillis() + timeoutMs
        while (!cond()) {
            check(System.currentTimeMillis() < until) { "не дождались: $what (журнал: ${log.all.takeLast(8)})" }
            Thread.sleep(POLL_MS)
        }
    }

    private fun reasonsAtCollector(): List<String> = collector.stored.values.sortedBy { it.long("seq") }.map { it.str("reason")!! }

    // ---------- доставка ----------

    @Test fun recordsReachTheCollectorSignedAndTheQueueDrains() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        val expected = playRun(f)
        w.start()
        await("записи у коллектора") { collector.stored.size == expected.size && queued(w) == 0 }
        assertEquals(expected, reasonsAtCollector())
        // коллектор сам проверил подпись и автора; здесь — что субъект один, ключ мира, и seq идёт подряд
        assertTrue(collector.stored.values.all { it.str("subjectKeyB64") == key.publicB64 && it.str("actor") == key.publicB64 })
        val seqs = collector.stored.values.map { it.long("seq") }.sorted()
        assertEquals((seqs.first() until seqs.first() + expected.size).toList(), seqs)
        assertTrue("свежая база начинает не с 1: $seqs", seqs.first() > 1_000_000L)
        // heartbeat: Мост называет себя ключом мира и сообщает глубину очереди
        val hb = collector.bodies.last()
        assertEquals(key.publicB64, hb.str("subjectKeyB64"))
        assertTrue(hb.getValue("presence").jsonObject.containsKey("pendingCount"))
    }

    @Test fun recordIsSentOnCommitNotOnTheIdlePoll() {
        // С быстрым опросом (fast) пропавшее пробуждение незаметно: простой в 30 мс сам находит запись. Здесь пауза простоя — минута,
        // так что запись уходит только если коммит разбудил отправку (store.addListener { recorder.committed(engine::wake) }).
        val f = ValueFixture(":memory:")
        val slow = SyncConfig(backoffMs = longArrayOf(20), idlePollMs = 60_000, noEndpointPollMs = 60_000, jitter = 0.0)
        val w = WorldSync(f.store, key, endpoint(), scope, config = slow, log = log)
        w.start()
        await("первый обмен с пустой очередью") { collector.changePosts.get() >= 1 && w.lastSummary.startsWith("ok") }
        Thread.sleep(SETTLE_MS) // цикл ушёл ждать паузу простоя: сигнал, пришедший раньше, потерялся бы
        val r = f.ops.submitDeck(f.test, "enter:e1", f.keyA, "Призрак", "t03", listOf("it_dA1", "it_dA2"), "it_dA1") // один коммит — одно пробуждение
        assertTrue(r.body.toString(), r.ok)
        await("запись у коллектора по коммиту", 5_000) { collector.stored.size == 1 && queued(w) == 0 }
        assertEquals(listOf("NET_ENTER"), reasonsAtCollector())
    }

    @Test fun lostResponseDoesNotDuplicateRecordsOnRetry() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        val expected = playRun(f)
        collector.dropNextResponse = true // коллектор принял пачку, но ответ до Моста не дошёл
        w.start()
        await("повторная отправка принята") { collector.stored.size == expected.size && queued(w) == 0 }
        val sent = collector.recordIdsSent.toList()
        assertTrue("пачка уходила повторно: $sent", sent.size >= expected.size * 2)
        assertEquals(expected.size, collector.stored.size) // дублей нет
        assertEquals(expected.size, sent.toSet().size) // и ни одного нового id при повторе
    }

    @Test fun collectorThatDoesNotAnnounceWorldRecordsGetsNothing() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        val expected = playRun(f)
        collector.capabilities = null // старый коллектор: ручки нет
        w.start()
        await("несколько проверок возможностей") { collector.capabilityGets.get() >= 3 }
        collector.capabilities = """{"world_records":0}"""
        collector.capabilityGets.set(0)
        await("ещё проверки при world_records=0") { collector.capabilityGets.get() >= 2 }
        collector.capabilities = """{"world_records":1}""" // коллектор до NET_BREACH: новой причины не знает, очередь не шлём
        collector.capabilityGets.set(0)
        await("ещё проверки при world_records=1") { collector.capabilityGets.get() >= 2 }
        collector.capabilities = """{"world_records":3}""" // формат новее нашего: тоже не шлём
        collector.capabilityGets.set(0)
        await("ещё проверки при world_records=3") { collector.capabilityGets.get() >= 2 }
        assertEquals(0, collector.changePosts.get())
        assertEquals(expected.size, queued(w)) // записи целы, ничего не потеряно
        collector.capabilities = """{"world_records":2}"""
        await("после объявления возможностей") { collector.stored.size == expected.size && queued(w) == 0 }
        assertTrue(log.has("world.capabilities"))
    }

    @Test fun recordsTheCollectorRejectsAreDroppedAndLogged() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        val expected = playRun(f)
        collector.unknownReasons = setOf("NET_EXIT") // коллектор без части причин (несогласованная версия)
        w.start()
        await("очередь пуста") { queued(w) == 0 && collector.stored.isNotEmpty() }
        assertEquals(expected.filter { it != "NET_EXIT" }, reasonsAtCollector())
        assertTrue(log.has("sync.rejected"))
    }

    @Test fun restoredCollectorReceivesAlreadyAcceptedRecordsAgain() {
        val f = ValueFixture(":memory:")
        val w = sync(f)
        val expected = playRun(f)
        w.start()
        await("первая доставка") { collector.stored.size == expected.size && queued(w) == 0 }
        collector.wipe() // восстановили из пустой копии: knownSeq = 0
        await("записи вернулись") { collector.stored.size == expected.size }
        assertEquals(expected, reasonsAtCollector())
        assertEquals(expected.size, collector.stored.size)
    }

    @Test fun resetBaseUnderTheSameKeyStillDeliversEverythingToTheCollector() {
        // Удалили только файл базы: ключ мира тот же, те же события, `ver` и номера транзакций снова с начала. Коллектор — как настоящий:
        // отвергает занятые id и занятые seq у этого ключа, а kit такие записи удаляет.
        val first = ValueFixture(":memory:")
        val w1 = sync(first)
        val expected = playRun(first)
        w1.start()
        await("первая база доставлена") { collector.stored.size == expected.size && queued(w1) == 0 }
        scope.cancel()
        first.store.close()

        val second = ValueFixture(":memory:")
        val later = Clock { System.currentTimeMillis() + HOUR_MS } // сброс случился позже: время идёт вперёд
        val w2 = WorldSync(second.store, key, endpoint(), scope2, clock = later, config = fast, log = log)
        playRun(second)
        w2.start()
        await("вторая база доставлена") { collector.stored.size == expected.size * 2 && queued(w2) == 0 }
        assertEquals(expected.size * 2, collector.stored.keys.toSet().size)
        assertTrue(log.all.toString(), !log.has("sync.rejected"))
    }

    @Test fun gameSecretIsSentAndWrongSecretKeepsTheQueue() {
        val f = ValueFixture(":memory:")
        collector.requiredSecret = "sekret"
        val bad = sync(f, endpoint("wrong"))
        val expected = playRun(f)
        bad.start()
        await("отказ по секрету") { collector.changePosts.get() >= 2 }
        assertEquals(0, collector.stored.size)
        assertEquals(expected.size, queued(bad))
        assertTrue(log.has("sync.http_error"))
        scope.cancel()

        val good = WorldSync(f.store, key, endpoint("sekret"), scope2, config = fast, log = log)
        good.start()
        await("доставка с верным секретом") { collector.stored.size == expected.size }
    }

    @Test fun secretThatCannotBeAHeaderNeverReachesTheLogAndKeepsTheQueue() {
        // Старт такой секрет отвергает (MainTest); если он всё же дошёл до транспорта, JDK бросает исключение с секретом в тексте,
        // а журнал не должен его повторять: ни значения, ни сообщения исключения.
        val f = ValueFixture(":memory:")
        val w = sync(f, endpoint("СЕКРЕТ\nQQMARKER"))
        val expected = playRun(f)
        w.start()
        await("отказ отправки записан в журнал") { log.has("sync.bad_") }
        assertTrue(log.all.toString(), log.all.none { "QQMARKER" in it || "СЕКРЕТ" in it })
        assertEquals(0, collector.changePosts.get())
        assertEquals(expected.size, queued(w)) // записи целы
    }

    @Test fun queueWaitsForCollectorAcrossBridgeRestart() {
        val path = tmp.root.resolve("q.db").path
        val first = ValueFixture(path)
        val offline = sync(first, null) // коллектор не задан: только копим
        val expected = playRun(first)
        offline.start()
        assertEquals(expected.size, queued(offline))
        first.store.close()
        assertEquals(0, collector.changePosts.get())

        val store = DocStore.open(path)
        val second = WorldSync(store, key, endpoint(), scope, config = fast, log = log)
        second.start()
        await("накопленное доставлено") { collector.stored.size == expected.size && queued(second) == 0 }
        assertEquals(expected, reasonsAtCollector())
        store.close()
    }

    // ---------- запуск целиком ----------

    @Test fun bridgeAppDeliversRecordsToTheCollectorFromTheLaunchFlag() {
        collector.requiredSecret = "sekret"
        val db = tmp.root.resolve("app.db").path
        val env = mapOf("NETRUN_KEY_WORLD" to "w", "NETRUN_KEY_MASTER" to "m", "NETRUN_COLLECTOR_SECRET" to "sekret")
        val options = parseLaunch(listOf("--port", "0", "--line-port", "0", "--db", db, "--collector", collector.url + "/"), env)
        BridgeApp(options, fast).use { app ->
            app.start()
            val s = app.store
            s.put("node", "node_07", 0, VJ.obj("tier" to VJ.p("STANDARD"), "lockdown_until" to VJ.p(0L), "eddies" to VJ.p(10L)))
            s.put("terminal", "t03", 0, VJ.obj("node" to VJ.p("node_07")))
            for (id in listOf("it_a", "it_b")) {
                s.put("item", id, 0, VJ.obj("owner" to VJ.p("inbox:KEY_A"), "kind" to VJ.p("DAEMON"), "payload" to VJ.p("p"), "protected" to VJ.p(false), "origin" to VJ.p("phone:KEY_A")))
            }
            s.put("runner", ValueOps.runnerDocId("KEY_A"), 0, VJ.obj("key" to VJ.p("KEY_A"), "callsign" to VJ.p("KEY_A"), "blocked" to VJ.p(false), "runs" to VJ.p(1L), "tutorial_done" to VJ.p(true)))
            val r = ValueOps(s).submitDeck(Caller(Role.TEST, "t"), "enter:1", "KEY_A", "Призрак", "t03", listOf("it_a", "it_b"), "it_a")
            assertTrue(r.body.toString(), r.ok)
            await("NET_ENTER у коллектора") { collector.stored.values.any { it.str("reason") == "NET_ENTER" } }
            val enter = collector.stored.values.single { it.str("reason") == "NET_ENTER" }
            assertEquals(app.worldKey.publicB64, enter.str("subjectKeyB64"))
            val value: JsonObject = Json.parseToJsonElement(enter.str("newValue")!!).jsonObject
            assertEquals("Призрак", VJ.str(value, "callsign"))
            assertTrue(collector.secretsSeen.all { it == "sekret" })
        }
    }

    private companion object {
        const val POLL_MS = 15L
        const val SETTLE_MS = 300L
        const val HOUR_MS = 3_600_000L
    }
}
