package com.megablok10.rules

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Таблица breach.md 2.2 и итог 2.6: что засчитывается до замка, что после, как ловушка рвёт замок. */
class BreachLockRuleTest {
    private val lock = listOf("1C", "55")
    private val chain = listOf("BD", "E9")

    private fun daemon(id: String, effect: DaemonEffect, seq: List<String> = chain) = Daemon(id, id, seq, Tier.BASE, effect)

    private fun matched(buffer: List<String>, effect: DaemonEffect, lockCodes: List<String> = lock) =
        resolveDaemons(buffer, listOf(daemon("d", effect)), lockCodes).isNotEmpty()

    private val lootEffects = listOf(DaemonEffect.EXTRACT_SHARD, DaemonEffect.EXTRACT_DAEMON, DaemonEffect.MINER)
    private val traceEffects = listOf(DaemonEffect.GHOST, DaemonEffect.TIMESKEW, DaemonEffect.BLACKOUT)

    private val chainThenLock = chain + lock
    private val lockThenChain = lock + chain

    @Test
    fun `loot counts only after the lock`() {
        for (e in lootEffects) {
            assertTrue("$e: после замка", matched(lockThenChain, e))
            assertFalse("$e: до замка", matched(chainThenLock, e))
            assertFalse("$e: замка нет вовсе", matched(chain, e))
            assertFalse("$e: замок вскрыт не целиком", matched(chain + lock.take(1), e))
        }
    }

    @Test
    fun `loot chain that overlaps the lock is not after it`() {
        // Замок [1C,55], цепочка [55,E9]: буфер 1C,55,E9 — цепочка начинается внутри замка, а не после него.
        val overlapping = Daemon("d", "d", listOf("55", "E9"), Tier.BASE, DaemonEffect.EXTRACT_SHARD)
        assertEquals(emptySet<String>(), resolveDaemons(listOf("1C", "55", "E9"), listOf(overlapping), lock))
        assertEquals(setOf("d"), resolveDaemons(listOf("1C", "55", "55", "E9"), listOf(overlapping), lock))
    }

    @Test
    fun `loot between two lock occurrences counts after the first one`() {
        assertTrue(matched(lock + chain + lock, DaemonEffect.EXTRACT_SHARD))
        // Цепочка до первого замка и ещё одна после — засчитана вторая.
        assertTrue(matched(chain + lock + chain, DaemonEffect.EXTRACT_SHARD))
    }

    @Test
    fun `traces count anywhere even before the lock or without it`() {
        for (e in traceEffects) {
            assertTrue("$e: после замка", matched(lockThenChain, e))
            assertTrue("$e: до замка", matched(chainThenLock, e))
            assertTrue("$e: без вскрытия замка", matched(chain, e))
        }
    }

    @Test
    fun `jitter and decrypt keep matching by chain anywhere`() {
        assertTrue(matched(chainThenLock, DaemonEffect.JITTER))
        assertTrue(matched(chain, DaemonEffect.DECRYPT))
    }

    @Test
    fun `without a lock everything matches anywhere as before`() {
        for (e in DaemonEffect.entries) {
            assertTrue("$e", matched(chain, e, lockCodes = emptyList()))
            assertTrue("$e без параметра замка", resolveDaemons(chain, listOf(daemon("d", e))).isNotEmpty())
        }
    }

    @Test
    fun `lock opened at is the end of the first full match`() {
        assertEquals(0, lockOpenedAt(listOf("BD"), emptyList()))
        assertEquals(2, lockOpenedAt(lock, lock))
        assertEquals(4, lockOpenedAt(chainThenLock, lock))
        assertNull(lockOpenedAt(listOf("1C", BreachSymbols.TRAP_SENTINEL, "55"), lock))
        assertNull(lockOpenedAt(listOf("1C"), lock))
    }

    // ── через попытку и итог ────────────────────────────────────────────────────────

    /**
     * Сетка 3×3 под замок [1C,55]; ход по правилу: (0,0) → столбец 0 → строка 1 → столбец 1.
     *   1C BD FF
     *   55 BD FF   ← строка 1: (1,0)=55 замок, (1,1)=BD
     *   FF E9 FF   ← столбец 1: (2,1)=E9
     */
    private val lockFirstGrid = BreachGrid(
        size = 3,
        cells = listOf(listOf("1C", "BD", "FF"), listOf("55", "BD", "FF"), listOf("FF", "E9", "FF")),
        lock = lock,
    )

    /**
     * Сетка 3×3: цепочка BD,E9 собирается первой, замок — после неё.
     *   BD FF FF
     *   E9 1C FF   ← (0,0)=BD, (1,0)=E9, (1,1)=1C
     *   FF 55 FF   ← (2,1)=55
     */
    private val lootFirstGrid = BreachGrid(
        size = 3,
        cells = listOf(listOf("BD", "FF", "FF"), listOf("E9", "1C", "FF"), listOf("FF", "55", "FF")),
        lock = lock,
    )

    private fun play(grid: BreachGrid, daemons: List<Daemon>, taps: List<Pair<Int, Int>>, bufferSize: Int = 4): BreachRun {
        var run = BreachRun(BreachAttemptState(grid, daemons, bufferSize), 45)
        taps.forEach { run = run.tap(it).run }
        return run.resolve()
    }

    private val extract = daemon("extract", DaemonEffect.EXTRACT_SHARD)

    @Test
    fun `lock first then loot is a success with the lock opened`() {
        val run = play(lockFirstGrid, listOf(extract), listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1))
        val r = run.result!!
        assertEquals(BreachOutcome.SUCCESS, r.outcome)
        assertTrue(r.lockOpened)
        assertEquals(emptySet<String>(), r.matchedBeforeLock)
    }

    @Test
    fun `loot before the lock is not counted and is reported as matched before`() {
        val run = play(lootFirstGrid, listOf(extract), listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1))
        val r = run.result!!
        assertEquals(BreachOutcome.FAIL, r.outcome)
        assertTrue(r.lockOpened)
        assertEquals(emptySet<String>(), r.matchedIds)
        assertEquals(setOf("extract"), r.matchedBeforeLock)
    }

    @Test
    fun `loot chain with the lock not opened stays uncounted`() {
        val run = play(lootFirstGrid, listOf(extract), listOf(0 to 0, 1 to 0))
        val r = run.result!!
        assertEquals(BreachOutcome.FAIL, r.outcome)
        assertFalse(r.lockOpened)
        assertEquals(setOf("extract"), r.matchedBeforeLock)
    }

    @Test
    fun `ghost before the lock is counted while loot before the lock is not - partial`() {
        val ghost = daemon("ghost", DaemonEffect.GHOST)
        val run = play(lootFirstGrid, listOf(extract, ghost), listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1))
        val r = run.result!!
        assertEquals(BreachOutcome.PARTIAL, r.outcome)
        assertEquals(setOf("ghost"), r.matchedIds)
        assertEquals(setOf("extract"), r.matchedBeforeLock)
    }

    @Test
    fun `a trap inside the lock breaks it and the loot after stays uncounted`() {
        val trapped = lockFirstGrid.copy(trapCells = setOf(1 to 0))
        val run = play(trapped, listOf(extract), listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1))
        val r = run.result!!
        assertFalse(r.lockOpened)
        assertEquals(BreachOutcome.FAIL, r.outcome)
        assertEquals(emptySet<String>(), r.matchedIds)
        assertEquals(setOf("extract"), r.matchedBeforeLock)
    }

    @Test
    fun `tap reports a new match only when the lock rule counts it`() {
        var run = BreachRun(BreachAttemptState(lootFirstGrid, listOf(extract), 4), 45)
        run = run.tap(0 to 0).run
        val second = run.tap(1 to 0)
        assertFalse("цепочка до замка не должна считаться совпадением", second.matched)
        assertFalse(second.run.attempt.lockOpened)
    }

    @Test
    fun `result keeps the two argument constructor and its outcome`() {
        val a = daemon("a", DaemonEffect.EXTRACT_SHARD)
        val b = daemon("b", DaemonEffect.GHOST)
        assertEquals(BreachOutcome.SUCCESS, BreachResult(listOf(a, b), setOf("a", "b")).outcome)
        assertEquals(BreachOutcome.PARTIAL, BreachResult(listOf(a, b), setOf("a")).outcome)
        assertEquals(BreachOutcome.FAIL, BreachResult(listOf(a, b), emptySet()).outcome)
        assertEquals(BreachOutcome.FAIL, BreachResult(emptyList(), emptySet()).outcome)
        assertFalse(BreachResult(listOf(a), setOf("a")).lockOpened)
    }

    @Test
    fun `without a lock the attempt reports no lock fields`() {
        val plain = lockFirstGrid.copy(lock = emptyList())
        val run = play(plain, listOf(extract), listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1))
        val r = run.result!!
        assertEquals(BreachOutcome.SUCCESS, r.outcome)
        assertFalse(r.lockOpened)
        assertEquals(emptySet<String>(), r.matchedBeforeLock)
    }
}
