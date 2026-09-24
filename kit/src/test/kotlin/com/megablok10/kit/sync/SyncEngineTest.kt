package com.megablok10.kit.sync

import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.time.Clock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Цикл обмена с мастерским сервером на виртуальном времени: никаких ожиданий, паузы проверяются до миллисекунды. */
@OptIn(ExperimentalCoroutinesApi::class)
class SyncEngineTest {
    private class FakeQueue : ChangeQueue {
        val rows = mutableListOf<ChangeRecord>()
        private var seq = 0L
        override suspend fun nextSeq() = ++seq
        override suspend fun insert(record: ChangeRecord) { if (rows.none { it.id == record.id }) rows += record }
        override suspend fun nextBatch(limit: Int) = rows.sortedBy { it.seq }.take(limit)
        override suspend fun deleteByIds(ids: List<String>) { rows.removeAll { it.id in ids } }
        override suspend fun count() = rows.size
        override suspend fun oldestHappenedAt() = rows.minOfOrNull { it.happenedAt }
    }

    /** Сервер: по умолчанию принимает всё; сценарий можно подменить очередью ответов. */
    private class FakeServer(private val now: () -> Long) : CollectorTransport {
        val requests = mutableListOf<Pair<Long, SyncRequest>>()
        val script = ArrayDeque<(SyncRequest) -> SyncResponse?>()
        override suspend fun exchange(endpoint: CollectorEndpoint, request: SyncRequest): SyncResponse? {
            requests += now() to request
            val next = script.removeFirstOrNull() ?: { r: SyncRequest -> SyncResponse(r.records.map { it.id }.toSet(), emptyMap(), emptyList()) }
            return next(request)
        }
    }

    private class Hooks : SyncHooks {
        val applied = mutableListOf<String>()
        val rejected = mutableListOf<Map<String, String>>()
        val peers = mutableListOf<List<PeerInfo>>()
        var poison: String? = null
        /** Правки, которые телефон отвергает сам: поле, которого эта версия не знает. */
        val unsupported = mutableSetOf<String>()
        override fun onServerPeers(peers: List<PeerInfo>, myPubKeyB64: String) { this.peers += peers }
        override suspend fun onRejected(rejected: Map<String, String>) { this.rejected += rejected }
        override suspend fun applyMasterChange(change: ChangeRecord): MasterApply {
            if (change.id == poison) error("ядовитая правка")
            if (change.id in unsupported) return MasterApply.Failed("поле не поддерживается", permanent = true)
            applied += change.id
            return MasterApply.Applied
        }
    }

    private fun rec(id: String, seq: Long, at: Long = 0) = ChangeRecord(id, "me", seq, at, "balance", null, "1", "X", null, "me", "sig")

    private class Env(scope: TestScope) {
        val queue = FakeQueue()
        val server = FakeServer { scope.testScheduler.currentTime }
        val hooks = Hooks()
        val log = RecordingLog()
        var endpoint: CollectorEndpoint? = CollectorEndpoint("http://10.10.0.1:8080", "secret")
        var subject: String? = "me"
        val presenceSeen = mutableListOf<QueueStats>()
        val engine = SyncEngine(
            queue, server, { endpoint }, { subject },
            presence = { stats -> presenceSeen += stats; mapOf("chatPort" to 4000) },
            hooks = hooks, clock = Clock { scope.testScheduler.currentTime }, log = log, tag = "ChangeRecordStore",
        )
        fun times() = server.requests.map { it.first }
    }

    private fun TestScope.started(): Env = Env(this).also { env -> backgroundScope.launch { env.engine.run() }; runCurrent() }

    @Test fun emptyQueueStillPollsForMasterChangesEveryIdleInterval() = runTest {
        val env = started()
        advanceTimeBy(65_000); runCurrent()
        assertEquals(listOf(0L, 30_000L, 60_000L), env.times())
        assertTrue(env.server.requests.all { it.second.records.isEmpty() && it.second.subjectKeyB64 == "me" })
        assertTrue(env.engine.lastSummary.startsWith("ok в "))
    }

    @Test fun noEndpointMeansNoRequestsUntilWoken() = runTest {
        val env = Env(this).apply { endpoint = null }
        backgroundScope.launch { env.engine.run() }
        advanceTimeBy(100_000); runCurrent()
        assertTrue(env.server.requests.isEmpty())
        env.endpoint = CollectorEndpoint("http://10.10.0.1:8080", null)
        env.engine.wake(); runCurrent()
        assertEquals(1, env.server.requests.size)
    }

    @Test fun recordsAreSentAndAcceptedOnesRemoved() = runTest {
        val env = Env(this)
        env.queue.insert(rec("b", 2)); env.queue.insert(rec("a", 1))
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertEquals(listOf("a", "b"), env.server.requests.first().second.records.map { it.id })
        assertTrue(env.queue.rows.isEmpty())
    }

    @Test fun wakeSendsNewRecordWithoutWaitingForIdlePoll() = runTest {
        val env = started()
        advanceTimeBy(5_000)
        env.queue.insert(rec("new", 1)); env.engine.wake(); runCurrent()
        // запись ушла сразу по пробуждению; за непустой пачкой — контрольный запрос без паузы (вдруг в очереди ещё есть)
        assertEquals(listOf(0L, 5_000L, 5_000L), env.times())
        assertEquals(listOf("new"), env.server.requests[1].second.records.map { it.id })
        assertTrue(env.queue.rows.isEmpty())
    }

    @Test fun unreachableServerBacksOffAndKeepsQueue() = runTest {
        val env = Env(this)
        env.queue.insert(rec("a", 1))
        repeat(7) { env.server.script += { null } }
        backgroundScope.launch { env.engine.run() }
        advanceTimeBy(1 + 1_000 + 2_000 + 5_000 + 15_000 + 60_000 + 60_000); runCurrent()
        // 1 → 2 → 5 → 15 → 60 → 60 с между попытками
        assertEquals(listOf(0L, 1_000L, 3_000L, 8_000L, 23_000L, 83_000L, 143_000L), env.times())
        assertEquals(1, env.queue.rows.size)
        assertTrue(env.engine.lastSummary.startsWith("нет связи в "))
        advanceTimeBy(60_000); runCurrent()
        assertTrue(env.queue.rows.isEmpty()) // связь вернулась — ушло
    }

    @Test fun rejectedRecordsAreDroppedAndReported() = runTest {
        val env = Env(this)
        env.queue.insert(rec("bad", 1)); env.queue.insert(rec("ok", 2))
        env.server.script += { SyncResponse(setOf("ok"), mapOf("bad" to "provision code already used"), emptyList()) }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertTrue(env.queue.rows.isEmpty())
        assertEquals(listOf(mapOf("bad" to "provision code already used")), env.hooks.rejected)
        assertTrue(env.log.has("W/ChangeRecordStore sync.rejected count=1"))
    }

    @Test fun masterChangesAreAppliedInOrderAndAckedImmediately() = runTest {
        val env = Env(this)
        env.server.script += { SyncResponse(emptySet(), emptyMap(), listOf(rec("m1", 10), rec("m2", 11))) }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertEquals(listOf("m1", "m2"), env.hooks.applied)
        assertEquals(listOf(0L, 0L), env.times()) // подтверждение — сразу, без паузы
        assertEquals(listOf("m1", "m2"), env.server.requests[1].second.ackIds)
        advanceTimeBy(30_001); runCurrent()
        assertTrue(env.server.requests[2].second.ackIds.isEmpty()) // сервер их учёл — повторно не шлём
    }

    @Test fun failedMasterChangeIsNotAckedButReportedAndRetried() = runTest {
        val env = Env(this).apply { hooks.poison = "m2" }
        // Сервер присылает правки, пока их не подтвердят: хорошая, плохая, снова хорошая.
        val unacked = mutableListOf(rec("m1", 10), rec("m2", 11), rec("m3", 12))
        repeat(3) {
            env.server.script += { r -> unacked.removeAll { it.id in r.ackIds }; SyncResponse(emptySet(), emptyMap(), unacked.toList()) }
        }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertEquals(listOf("m1", "m3"), env.hooks.applied)
        val second = env.server.requests[1].second
        assertEquals("подтверждены только применённые", listOf("m1", "m3"), second.ackIds)
        assertEquals(listOf(ApplyFailure("m2", "IllegalStateException: ядовитая правка", permanent = false)), second.failures)
        assertTrue(env.log.has("не удалось применить правку m2"))

        // Неприменённая правка пришла снова — повтор не раньше обычного опроса, без тугого цикла запросов.
        assertEquals(2, env.server.requests.size)
        env.hooks.poison = null
        advanceTimeBy(30_001); runCurrent()
        assertEquals(listOf("m1", "m3", "m2"), env.hooks.applied)
        // Третий запрос несёт отказ по второй попытке, четвёртый — подтверждение удачной третьей.
        assertEquals(listOf("m2"), env.server.requests[2].second.failures.map { it.id })
        assertEquals(listOf("m2"), env.server.requests[3].second.ackIds)
        assertTrue(env.server.requests[3].second.failures.isEmpty())
    }

    @Test fun permanentlyUnsupportedMasterChangeIsReportedAsSuch() = runTest {
        val env = Env(this).apply { hooks.unsupported += "m1" }
        env.server.script += { SyncResponse(emptySet(), emptyMap(), listOf(rec("m1", 10))) }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        advanceTimeBy(30_001); runCurrent()
        val next = env.server.requests[1].second
        assertTrue(next.ackIds.isEmpty())
        assertEquals(listOf(ApplyFailure("m1", "поле не поддерживается", permanent = true)), next.failures)
        assertTrue(env.log.has("master.apply_failed"))
    }


    @Test fun acksSurviveAFailedRequest() = runTest {
        val env = Env(this)
        env.server.script += { SyncResponse(emptySet(), emptyMap(), listOf(rec("m1", 10))) }
        env.server.script += { null }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        advanceTimeBy(1_000); runCurrent()
        assertEquals(listOf("m1"), env.server.requests[1].second.ackIds)
        assertEquals(listOf("m1"), env.server.requests[2].second.ackIds)
    }

    @Test fun crashingIterationBacksOffInsteadOfStoppingTheLoop() = runTest {
        val env = Env(this)
        env.server.script += { error("200 с не-JSON телом") }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertTrue(env.engine.lastSummary.startsWith("упал IllegalStateException"))
        advanceTimeBy(1_000); runCurrent()
        assertEquals(listOf(0L, 1_000L), env.times())
    }

    @Test fun fullBatchIsFollowedByNextBatchWithoutPause() = runTest {
        val env = Env(this)
        repeat(450) { env.queue.insert(rec("r$it", it.toLong())) }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertEquals(listOf(200, 200, 50, 0), env.server.requests.map { it.second.records.size })
        assertEquals(listOf(0L, 0L, 0L, 0L), env.times())
    }

    @Test fun heartbeatCarriesQueueStatsAndOnlyWithIdentity() = runTest {
        val env = Env(this)
        env.queue.insert(rec("old", 1, at = -40_000))
        env.server.script += { SyncResponse(emptySet(), emptyMap(), emptyList()) }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertEquals(QueueStats(1, 40_000), env.presenceSeen.first())
        assertEquals(mapOf("chatPort" to 4000), env.server.requests.first().second.presence)

        val anon = Env(this).apply { subject = null }
        backgroundScope.launch { anon.engine.run() }; runCurrent()
        assertEquals(null, anon.server.requests.first().second.presence)
        assertTrue(anon.presenceSeen.isEmpty())
    }

    @Test fun serverPeerHintsOnlyWithIdentity() = runTest {
        val peer = PeerInfo("bob", "Bob", "F", "10.10.0.2", 4000)
        val env = Env(this)
        env.server.script += { SyncResponse(emptySet(), emptyMap(), emptyList(), listOf(peer)) }
        backgroundScope.launch { env.engine.run() }; runCurrent()
        assertEquals(listOf(listOf(peer)), env.hooks.peers)

        val anon = Env(this).apply { subject = null }
        anon.server.script += { SyncResponse(emptySet(), emptyMap(), emptyList(), listOf(peer)) }
        backgroundScope.launch { anon.engine.run() }; runCurrent()
        assertTrue(anon.hooks.peers.isEmpty())
    }
}
