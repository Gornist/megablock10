package com.megablok10.app.presence

import org.junit.Assert.assertEquals
import org.junit.Test

/** Разрешение сервисов по одному: пачка находок на площадке не должна терять игроков на FAILURE_ALREADY_ACTIVE. */
class NsdResolveQueueTest {
    private val calls = mutableListOf<String>()
    private var now = 0L
    private val timers = mutableListOf<Pair<Long, () -> Unit>>()
    private val scheduler = NsdScheduler { delay, block ->
        val timer = (now + delay) to block
        timers += timer
        return@NsdScheduler { timers.remove(timer) }
    }
    private val q = NsdResolveQueue<String>({ it }, { item, token -> calls += "$item#$token" }, scheduler, timeoutMs = 10_000, retryMs = 1_000, maxAttempts = 3)

    private fun advance(ms: Long) {
        now += ms
        timers.filter { it.first <= now }.forEach { t -> if (timers.remove(t)) t.second() }
    }

    @Test fun burstIsResolvedOneByOne() {
        q.add("a"); q.add("b"); q.add("c")
        assertEquals(listOf("a#1"), calls)
        q.onResolved(1)
        q.onResolved(2)
        assertEquals(listOf("a#1", "b#2", "c#3"), calls)
    }

    @Test fun sameServiceFoundTwiceIsResolvedOnce() {
        q.add("a"); q.add("b"); q.add("a"); q.add("b")
        q.onResolved(1); q.onResolved(2)
        assertEquals(listOf("a#1", "b#2"), calls)
    }

    @Test fun busyIsRetriedAfterAPauseThenGivenUp() {
        q.add("a"); q.add("b")
        q.onFailed(1, busy = true)
        assertEquals("пауза, и b не лезет вперёд", listOf("a#1"), calls)
        advance(1_000)
        assertEquals(listOf("a#1", "a#2"), calls)
        q.onFailed(2, busy = true)
        advance(1_000)
        q.onFailed(3, busy = true) // третья попытка — хватит
        assertEquals(listOf("a#1", "a#2", "a#3", "b#4"), calls)
    }

    @Test fun otherFailureMovesOn() {
        q.add("a"); q.add("b")
        q.onFailed(1, busy = false)
        assertEquals(listOf("a#1", "b#2"), calls)
    }

    @Test fun lostAnswerTimesOut() {
        q.add("a"); q.add("b")
        advance(10_000)
        assertEquals(listOf("a#1", "b#2"), calls)
        q.onResolved(1) // запоздалый — не в счёт
        assertEquals(1, q.pending)
    }

    @Test fun removedAndClearedAreNotResolved() {
        q.add("a"); q.add("b"); q.add("c")
        q.remove("b")
        q.onResolved(1)
        assertEquals(listOf("a#1", "c#2"), calls)
        q.clear()
        q.onResolved(2)
        assertEquals(0, q.pending)
    }
}
