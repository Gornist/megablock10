package com.megablok10.kit.mesh

import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.time.ManualClock
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Очередь исходящих при обрывах и роуминге: что уходит, что ждёт, что выбрасывается. */
class OutboxTest {
    private class FakeQueue : OutboxQueue {
        val rows = mutableListOf<OutboxEntry>()
        private var nextId = 1L
        fun add(to: String, createdAt: Long = 0, next: Long = 0, attempts: Int = 0) =
            OutboxEntry(nextId++, to, "line-$to-$nextId", createdAt, attempts, next).also { rows += it }
        override suspend fun insert(toPubKeyB64: String, line: String, createdAt: Long) { rows += OutboxEntry(nextId++, toPubKeyB64, line, createdAt) }
        override suspend fun due(now: Long) = rows.filter { it.nextAttemptAt <= now }.sortedBy { it.id }
        override suspend fun delete(id: Long) { rows.removeAll { it.id == id } }
        override suspend fun reschedule(id: Long, attempts: Int, nextAttemptAt: Long) {
            rows.replaceAll { if (it.id == id) it.copy(attempts = attempts, nextAttemptAt = nextAttemptAt) else it }
        }
        override suspend fun deleteOlderThan(cutoff: Long): Int = rows.count { it.createdAt < cutoff }.also { rows.removeAll { r -> r.createdAt < cutoff } }
        override suspend fun count() = rows.size
    }

    private val bob = setOf("bob")
    private val now = 1_000_000L
    private val schedule = OutboxSchedule()

    private suspend fun flush(queue: OutboxQueue, visible: Set<String>, at: Long, send: suspend (String, String) -> Boolean) =
        Outbox(queue, schedule, send = send).flush(visible, at)

    @Test fun invisiblePeerKeepsMessageWithoutCountingAttempt() = runTest {
        val q = FakeQueue().apply { add("bob") }
        val sent = flush(q, emptySet(), now) { _, _ -> error("не должно отправляться") }
        assertEquals(0, sent)
        assertEquals(0, q.rows.single().attempts)
    }

    @Test fun visiblePeerGetsMessageAndRowIsRemoved() = runTest {
        val q = FakeQueue().apply { add("bob") }
        val got = mutableListOf<String>()
        val sent = flush(q, bob, now) { to, line -> got += "$to:$line"; true }
        assertEquals(1, sent)
        assertTrue(q.rows.isEmpty())
        assertEquals(1, got.size)
    }

    @Test fun failedSendBacksOffAndRetriesLater() = runTest {
        val q = FakeQueue().apply { add("bob") }
        assertEquals(0, flush(q, bob, now) { _, _ -> false })
        val row = q.rows.single()
        assertEquals(1, row.attempts)
        assertEquals(now + schedule.nextDelayMs(1), row.nextAttemptAt)
        // до срока не пробуем
        assertEquals(0, flush(q, bob, now + 1) { _, _ -> error("рано") })
        // после срока уходит
        assertEquals(1, flush(q, bob, row.nextAttemptAt) { _, _ -> true })
        assertTrue(q.rows.isEmpty())
    }

    @Test fun messagesOlderThanMaxAgeAreDropped() = runTest {
        val q = FakeQueue().apply { add("bob", createdAt = now - schedule.maxAgeMs - 1); add("bob", createdAt = now) }
        val sent = flush(q, bob, now) { _, _ -> true }
        assertEquals(1, sent)
        assertTrue(q.rows.isEmpty())
    }

    @Test fun orderIsPreservedAndOtherPeersDontBlockTheQueue() = runTest {
        val q = FakeQueue().apply { add("alice"); add("bob"); add("bob") }
        val order = mutableListOf<Long>()
        flush(q, bob, now) { _, line -> order += line.substringAfterLast('-').toLong(); true }
        assertEquals(order.sorted(), order)
        assertEquals(listOf("alice"), q.rows.map { it.toPubKeyB64 })
    }

    @Test fun oneFailureDoesNotStopOtherMessages() = runTest {
        val q = FakeQueue().apply { add("bob"); add("bob") }
        var n = 0
        val sent = flush(q, bob, now) { _, _ -> ++n == 2 }
        assertEquals(1, sent)
        assertEquals(1, q.rows.size)
        assertEquals(1, q.rows.single().attempts)
    }

    @Test fun enqueueStampsCreationTimeFromClock() = runTest {
        val q = FakeQueue()
        val clock = ManualClock(now)
        Outbox(q, clock = clock) { _, _ -> true }.enqueue("bob", "MB10CHAT:v1:x")
        assertEquals(listOf(OutboxEntry(1, "bob", "MB10CHAT:v1:x", now)), q.rows)
    }

    @Test fun concurrentFlushesNeverSendTheSameRowTwice() = runTest {
        val q = FakeQueue().apply { repeat(5) { add("bob") } }
        val sentLines = mutableListOf<String>()
        val outbox = Outbox(q, schedule) { _, line -> sentLines += line; true }
        List(4) { async { outbox.flush(bob, now) } }.awaitAll()
        assertEquals(5, sentLines.size)
        assertEquals(5, sentLines.toSet().size)
    }

    @Test fun logKeepsEventNamesUsedInFieldLogAnalysis() = runTest {
        val q = FakeQueue().apply { add("bob"); add("bob") }
        val log = RecordingLog()
        var n = 0
        Outbox(q, schedule, log = log, tag = "OutboxStore") { _, _ -> ++n == 1 }.flush(bob, now)
        assertTrue(log.has("I/OutboxStore outbox.sent"))
        assertTrue(log.has("W/OutboxStore outbox.retry"))
        assertTrue(log.has("I/OutboxStore outbox.flushed sent=1 left=1"))
    }

    @Test fun defaultScheduleGrowsAndIsCapped() {
        assertEquals(listOf(2_000L, 4_000L, 8_000L, 15_000L, 30_000L, 60_000L), (0..5).map { schedule.nextDelayMs(it) })
        assertEquals(60_000L, schedule.nextDelayMs(50))
        assertEquals(2_000L, schedule.nextDelayMs(-3))
        assertEquals(12L * 60 * 60 * 1000, schedule.maxAgeMs)
        assertThrows(IllegalArgumentException::class.java) { OutboxSchedule(LongArray(0)) }
    }
}
