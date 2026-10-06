package com.megablok10.rules

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Щуп сложности взлома (breach.md, разделы 4 и 5): эталонная дека тира × 1000 зёрен. Решатель берёт добычу всегда, «жадный» бот
 * (смотрит на ход вперёд) и бот «3 хода» — в коридоре ниже. Ловушки-приманки боты не замечают (видят только мёртвые клетки), так что
 * бот «3 хода» слабее внимательного человека. Правка параметров тира без правки коридора — красный CI; правка коридора видна в диффе.
 *
 * Боты повторяют модель docs/gamedesign/model/breach_model.py; доля — «добыча засчитана по правилам замка» (вскрытие, потом цепочка).
 */
class BreachDifficultyProbeTest {
    /** Коридор в процентах (breach.md, раздел 4): минимум и максимум доли успеха бота. */
    private class Corridor(val greedy: IntRange, val thinker: IntRange)

    private val corridor = mapOf(
        Tier.BASE to Corridor(greedy = 65..100, thinker = 85..100),
        Tier.HARD to Corridor(greedy = 30..60, thinker = 60..100),
        Tier.NIGHTMARE to Corridor(greedy = 0..30, thinker = 40..100),
    )

    private val seeds = 1000

    /** [solver] = -1 — решатель не запускали (на старых параметрах он упирается в бюджет перебора и занимает минуты). */
    private class Rates(val solver: Int, val greedy: Int, val thinker: Int) {
        override fun toString() = "решатель ${if (solver < 0) "—" else "$solver %"}, жадный $greedy %, «3 хода» $thinker %"
    }

    /** Где доля вышла из коридора тира: пустой список — в коридоре. Решатель обязан быть 100 %. */
    private fun violations(tier: Tier, r: Rates): List<String> {
        val c = corridor.getValue(tier)
        return buildList {
            if (r.solver in 0..99) add("решатель ${r.solver} % вместо 100 %")
            if (r.greedy !in c.greedy) add("жадный ${r.greedy} % вне ${c.greedy}")
            if (r.thinker !in c.thinker) add("«3 хода» ${r.thinker} % вне ${c.thinker}")
        }
    }

    // ── колода и прогон ─────────────────────────────────────────────────────────────

    /** Эталонная дека тира — один демон Извлечения с цепочкой 2 / 3 / 4 (breach.md 6.1); буфер — «замок + демон + запас тира». */
    private fun referenceRates(tier: Tier): Rates {
        val params = BreachTierParams.forTier(tier)
        val len = 1 + tier.level
        val buffer = BreachTierParams.bufferSize(ram = 99, lockLength = params.lockLength, daemonsLen = len, tier = tier)
        return probe(params, listOf(len), params.lockLength, buffer)
    }

    private fun probe(params: BreachParams, daemonLens: List<Int>, lockLength: Int, bufferSize: Int, withSolver: Boolean = true): Rates {
        var solver = 0
        var greedy = 0
        var thinker = 0
        for (seed in 1L..seeds) {
            val random = Random(seed)
            val daemons = daemonLens.mapIndexed { i, len ->
                Daemon("d$i", "d$i", List(len) { BreachSymbols.ALPHABET.random(random) }, effect = DaemonEffect.EXTRACT_SHARD)
            }
            val grid = generateGrid(params.gridSize, daemons, random, params, lockLength)
            val start = BreachAttemptState(grid, daemons, bufferSize)
            val loot = daemons.first()
            val targets = listOfNotNull(grid.lock.takeIf { it.isNotEmpty() }) + daemons.map { it.sequence }
            val botRandom = Random(seed + 7_000_003)

            if (withSolver) {
                val solved = BreachAutoSolver.solve(start).fold(start) { s, cell -> s.select(cell) }
                if (solved.matchedDaemonIds.size == daemons.size) solver++
            }
            if (loot.id in greedyBot(start, targets, botRandom).matchedDaemonIds) greedy++
            if (loot.id in thinkerBot(start, targets, loot, botRandom).matchedDaemonIds) thinker++
        }
        return Rates(if (withSolver) solver * 100 / seeds else -1, greedy * 100 / seeds, thinker * 100 / seeds)
    }

    @Test
    fun `reference decks stay in the corridor`() {
        val report = Tier.entries.associateWith(::referenceRates)
        report.forEach { (tier, r) -> println("щуп $tier: $r") }
        val broken = report.flatMap { (tier, r) -> violations(tier, r).map { "$tier: $it" } }
        assertTrue("сложность вне коридора breach.md 4 (${report.entries.joinToString("; ") { "${it.key}: ${it.value}" }}): $broken", broken.isEmpty())
    }

    /**
     * Щуп должен краснеть на старых параметрах (breach.md 4, «Сейчас»): без замка, буфер = вся RAM, приманок на HARD нет. Тест держит это
     * в наборе: если старые параметры вдруг уложатся в коридор, коридор перестал что-либо проверять.
     */
    @Test
    fun `old parameters without lock break the corridor`() {
        data class Old(val tier: Tier, val params: BreachParams, val lens: List<Int>, val ram: Int)
        val old = listOf(
            Old(Tier.BASE, BreachParams(5, 45, 0..0, 0..0), listOf(2), 6),
            Old(Tier.HARD, BreachParams(6, 60, 2..3, 0..0), listOf(3, 3), 8),
            Old(Tier.NIGHTMARE, BreachParams(7, 75, 5..6, 2..3), listOf(3, 4), 10),
        )
        val broken = old.map { o ->
            val rates = probe(o.params, o.lens, lockLength = 0, bufferSize = o.ram, withSolver = false)
            println("щуп старые параметры ${o.tier}: $rates")
            o.tier to violations(o.tier, rates)
        }.filter { it.second.isNotEmpty() }.map { it.first }
        assertEquals("со старыми параметрами должны краснеть HARD и NIGHTMARE", listOf(Tier.HARD, Tier.NIGHTMARE), broken)
    }

    /** Только замок и снимаем с новых параметров тира: без него жадный бот снова берёт добычу слишком часто — замок и есть рычаг. */
    @Test
    fun `new tier params without the lock break the corridor`() {
        val broken = listOf(Tier.HARD, Tier.NIGHTMARE).filter { tier ->
            val params = BreachTierParams.forTier(tier)
            val len = 1 + tier.level
            val buffer = BreachTierParams.bufferSize(ram = 99, lockLength = 0, daemonsLen = len, tier = tier)
            val rates = probe(params, listOf(len), lockLength = 0, bufferSize = buffer, withSolver = false)
            println("щуп без замка $tier: $rates")
            violations(tier, rates).isNotEmpty()
        }
        assertEquals("без замка должны краснеть HARD и NIGHTMARE", listOf(Tier.HARD, Tier.NIGHTMARE), broken)
    }

    // ── боты ────────────────────────────────────────────────────────────────────────

    /** Клетки, которые видит игрок как допустимые: мёртвые (××) обходит, приманки от обычных кодов не отличает. */
    private fun visibleMoves(s: BreachAttemptState): List<Pair<Int, Int>> =
        s.selectableCells().filter { s.grid.codeAt(it) != BreachSymbols.DEAD_MARKER }

    private fun containsAnywhere(buffer: List<String>, chain: List<String>): Boolean =
        buffer.size >= chain.size && (0..buffer.size - chain.size).any { buffer.subList(it, it + chain.size) == chain }

    /** Длина самого длинного хвоста буфера, который является началом цепочки (но не ею целиком). */
    private fun tailProgress(buffer: List<String>, chain: List<String>): Int {
        for (len in minOf(chain.size - 1, buffer.size) downTo 1) {
            if (buffer.subList(buffer.size - len, buffer.size) == chain.subList(0, len)) return len
        }
        return 0
    }

    /** Жадный: ближайшая несобранная цель, клетка со следующим нужным кодом (иначе — с её первым кодом, иначе любая). */
    private fun greedyBot(start: BreachAttemptState, targets: List<List<String>>, random: Random): BreachAttemptState {
        var s = start
        while (!s.isFull) {
            val moves = visibleMoves(s)
            val todo = targets.filter { !containsAnywhere(s.matchCodes, it) }
            if (moves.isEmpty() || todo.isEmpty()) break
            val target = todo.first()
            val k = tailProgress(s.matchCodes, target)
            val good = moves.filter { s.grid.codeAt(it) == target[k] }
                .ifEmpty { if (k > 0) moves.filter { s.grid.codeAt(it) == target[0] } else emptyList() }
            s = s.select((good.ifEmpty { moves }).random(random))
        }
        return s
    }

    /** Думающий: перебирает [DEPTH] хода вперёд, приманок не замечает (в расчёте код приманки — обычный код). */
    private fun thinkerBot(start: BreachAttemptState, targets: List<List<String>>, loot: Daemon, random: Random): BreachAttemptState {
        val grid = start.grid
        val size = grid.size

        fun lootOk(b: List<String>) = loot.id in resolveDaemons(b, listOf(loot), grid.lock)

        fun score(b: List<String>): Int {
            val todo = targets.filter { !containsAnywhere(b, it) }
            val progress = if (todo.isEmpty()) 0 else tailProgress(b, todo.first())
            return (if (lootOk(b)) LOOT_WEIGHT else 0) + (targets.size - todo.size) * CHAIN_WEIGHT + progress
        }

        fun moves(path: List<Pair<Int, Int>>, visited: Set<Pair<Int, Int>>): List<Pair<Int, Int>> {
            val cells = if (path.isEmpty()) (0 until size).map { 0 to it }
            else candidatesFor(path.last(), nextLinkDimension(path.size), size, visited)
            return cells.filter { grid.codeAt(it) != BreachSymbols.DEAD_MARKER }
        }

        fun best(path: List<Pair<Int, Int>>, visited: Set<Pair<Int, Int>>, buffer: List<String>, depth: Int): Int {
            val sc = score(buffer)
            if (depth == 0 || buffer.size >= start.bufferSize || sc >= LOOT_WEIGHT) return sc
            return maxOf(sc, moves(path, visited).maxOfOrNull { m -> best(path + m, visited + m, buffer + grid.codeAt(m), depth - 1) } ?: sc)
        }

        var s = start
        while (!s.isFull && !(lootOk(s.matchCodes) && targets.all { containsAnywhere(s.matchCodes, it) })) {
            val path = s.selected
            val visited = path.toSet()
            val pick = moves(path, visited).maxByOrNull { m ->
                // Пара (оценка, случайный довесок) в одно число: довесок меньше единицы оценки.
                best(path + m, visited + m, s.matchCodes + grid.codeAt(m), DEPTH - 1) + random.nextDouble()
            } ?: break
            s = s.select(pick)
        }
        return s
    }

    private companion object {
        const val DEPTH = 3
        const val LOOT_WEIGHT = 10_000
        const val CHAIN_WEIGHT = 100
    }
}
