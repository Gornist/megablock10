package com.megablok10.app.chat

import com.megablok10.app.data.OutboxDao
import com.megablok10.app.data.OutboxEntity
import com.megablok10.app.presence.PeerInfo
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Очередь исходящих при обрывах и роуминге: что уходит, что ждёт, что выбрасывается. */
class OutboxFlushTest {
    private class FakeDao : OutboxDao {
        val rows = mutableListOf<OutboxEntity>()
        private var nextId = 1L
        fun add(to: String, createdAt: Long = 0, next: Long = 0, attempts: Int = 0) = OutboxEntity(nextId++, to, "line-$to-${nextId}", createdAt, attempts, next).also { rows += it }
        override suspend fun insert(entry: OutboxEntity): Long = add(entry.toPubKeyB64, entry.createdAt).id
        override suspend fun due(now: Long) = rows.filter { it.nextAttemptAt <= now }.sortedBy { it.id }
        override suspend fun delete(id: Long) { rows.removeAll { it.id == id } }
        override suspend fun reschedule(id: Long, attempts: Int, nextAttemptAt: Long) {
            rows.replaceAll { if (it.id == id) it.copy(attempts = attempts, nextAttemptAt = nextAttemptAt) else it }
        }
        override suspend fun deleteOlderThan(cutoff: Long): Int = rows.count { it.createdAt < cutoff }.also { rows.removeAll { r -> r.createdAt < cutoff } }
        override suspend fun count() = rows.size
    }

    private val bob = PeerInfo("bob", "Bob", "F", "10.10.0.2", 4000)
    private val now = 1_000_000L

    @Test fun invisiblePeerKeepsMessageWithoutCountingAttempt() = runTest {
        val dao = FakeDao().apply { add("bob") }
        val sent = flushOutbox(dao, emptyMap(), now) { _, _ -> error("не должно отправляться") }
        assertEquals(0, sent)
        assertEquals(0, dao.rows.single().attempts)
    }

    @Test fun visiblePeerGetsMessageAndRowIsRemoved() = runTest {
        val dao = FakeDao().apply { add("bob") }
        val got = mutableListOf<String>()
        val sent = flushOutbox(dao, mapOf("bob" to bob), now) { p, line -> got += "${p.host}:$line"; true }
        assertEquals(1, sent)
        assertTrue(dao.rows.isEmpty())
        assertEquals(1, got.size)
    }

    @Test fun failedSendBacksOffAndRetriesLater() = runTest {
        val dao = FakeDao().apply { add("bob") }
        assertEquals(0, flushOutbox(dao, mapOf("bob" to bob), now) { _, _ -> false })
        val row = dao.rows.single()
        assertEquals(1, row.attempts)
        assertEquals(now + OutboxPolicy.nextDelayMs(1), row.nextAttemptAt)
        // до срока не пробуем
        assertEquals(0, flushOutbox(dao, mapOf("bob" to bob), now + 1) { _, _ -> error("рано") })
        // после срока уходит
        assertEquals(1, flushOutbox(dao, mapOf("bob" to bob), row.nextAttemptAt) { _, _ -> true })
        assertTrue(dao.rows.isEmpty())
    }

    @Test fun messagesOlderThanMaxAgeAreDropped() = runTest {
        val dao = FakeDao().apply { add("bob", createdAt = now - OutboxPolicy.MAX_AGE_MS - 1); add("bob", createdAt = now) }
        val sent = flushOutbox(dao, mapOf("bob" to bob), now) { _, _ -> true }
        assertEquals(1, sent)
        assertTrue(dao.rows.isEmpty())
    }

    @Test fun orderIsPreservedAndOtherPeersDontBlockTheQueue() = runTest {
        val dao = FakeDao().apply { add("alice"); add("bob"); add("bob") }
        val order = mutableListOf<Long>()
        flushOutbox(dao, mapOf("bob" to bob), now) { _, line -> order += line.substringAfterLast('-').toLong(); true }
        assertEquals(order.sorted(), order)
        assertEquals(listOf("alice"), dao.rows.map { it.toPubKeyB64 })
    }

    @Test fun oneFailureDoesNotStopOtherMessages() = runTest {
        val dao = FakeDao().apply { add("bob"); add("bob") }
        var n = 0
        val sent = flushOutbox(dao, mapOf("bob" to bob), now) { _, _ -> ++n == 2 }
        assertEquals(1, sent)
        assertEquals(1, dao.rows.size)
        assertEquals(1, dao.rows.single().attempts)
    }
}
