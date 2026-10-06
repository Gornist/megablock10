package com.megablok10.rules

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.random.Random

/**
 * Golden-наборы поведения взлома для GDScript-порта (design §10.4): netrun/tests/fixtures/breach_golden.json.
 * Сетки, ловушки и демоны записаны в файл явно (порту не нужен Random Kotlin) — gdUnit проигрывает шаги и сверяет доступные
 * клетки, совпавших, исход и реплики таймера. Здесь два теста: [golden file replays on the rules] проигрывает файл по логике :rules
 * (ловит смену поведения), а при UPDATE_NETRUN_JSON=1 файл сначала пересоздаётся по [build] (так он и появился).
 */
class BreachGoldenTest {
    /** [lock] — попытка с замком хранилища длиной по тиру (Взлом 2.0): в файле у неё есть поле `lock`, у остальных спецификаций его нет. */
    private data class Spec(
        val name: String, val tier: Tier, val seed: Long, val daemons: List<Daemon>, val bufferSize: Int, val decrypt: Boolean,
        val script: Script, val lock: Boolean = false
    )
    private enum class Script { SOLVER, WALK, TRAP_FIRST, FIRST_MATCH_THEN_TIMEOUT, NO_TAPS_TIMEOUT }

    private fun d(id: String, vararg codes: String, tier: Tier = Tier.BASE, effect: DaemonEffect = DaemonEffect.EXTRACT_SHARD) =
        Daemon(id, id, codes.toList(), tier, effect)

    private val specs = listOf(
        Spec("base_one_daemon_solver", Tier.BASE, 1, listOf(d("a", "1C", "55")), 6, false, Script.SOLVER),
        Spec("base_two_daemons_solver", Tier.BASE, 2, listOf(d("a", "1C", "55"), d("b", "BD", "E9", "7A")), 6, false, Script.SOLVER),
        Spec("base_two_daemons_walk", Tier.BASE, 3, listOf(d("a", "1C", "55"), d("b", "BD", "E9")), 6, false, Script.WALK),
        Spec("hard_two_daemons_solver", Tier.HARD, 4, listOf(d("a", "55", "BD"), d("b", "E9", "7A", "FF")), 8, false, Script.SOLVER),
        Spec("hard_walk_with_dead_cells", Tier.HARD, 5, listOf(d("a", "55", "BD", "1C")), 7, false, Script.WALK),
        Spec("hard_trap_first", Tier.HARD, 6, listOf(d("a", "1C", "FF")), 6, false, Script.TRAP_FIRST),
        Spec("nightmare_solver", Tier.NIGHTMARE, 7, listOf(d("a", "E9", "7A"), d("b", "FF", "1C", "55")), 8, false, Script.SOLVER),
        Spec("nightmare_walk_corrupted", Tier.NIGHTMARE, 8, listOf(d("a", "7A", "FF", "BD")), 8, false, Script.WALK),
        Spec("nightmare_trap_first", Tier.NIGHTMARE, 9, listOf(d("a", "1C", "55", "BD")), 8, false, Script.TRAP_FIRST),
        Spec("base_partial_timeout", Tier.BASE, 13, listOf(d("a", "1C", "55"), d("b", "BD", "E9", "7A")), 6, false, Script.FIRST_MATCH_THEN_TIMEOUT),
        Spec("hard_partial_timeout", Tier.HARD, 14, listOf(d("a", "55", "BD"), d("b", "E9", "7A")), 7, false, Script.FIRST_MATCH_THEN_TIMEOUT),
        Spec("nightmare_no_taps_timeout", Tier.NIGHTMARE, 15, listOf(d("a", "1C", "55")), 6, false, Script.NO_TAPS_TIMEOUT),
        Spec("decrypt_tier1_solver", Tier.BASE, 10, listOf(decryptTarget(1, 10)), 3 + BreachConstants.DECRYPT_BUFFER_EXTRA, true, Script.SOLVER),
        Spec("decrypt_tier2_solver", Tier.HARD, 11, listOf(decryptTarget(2, 11)), 4 + BreachConstants.DECRYPT_BUFFER_EXTRA, true, Script.SOLVER),
        Spec("decrypt_tier3_walk", Tier.NIGHTMARE, 12, listOf(decryptTarget(3, 12)), 5 + BreachConstants.DECRYPT_BUFFER_EXTRA, true, Script.WALK),
    ) + lockSpecs()

    /** Буфер попытки с замком: наименьшее из RAM и «замок + демоны + запас тира» — то, что считает приложение (BreachTierParams.bufferSize). */
    private fun lockedBuffer(tier: Tier, ram: Int, daemons: List<Daemon>) =
        BreachTierParams.bufferSize(ram, BreachTierParams.forTier(tier).lockLength, daemons.sumOf { it.sequence.size }, tier)

    /** Два набора с замком на тир (breach.md 2.1, 2.2): решатель с двумя эффектами и ход, дающий ловушки или обычную ходьбу. */
    private fun lockSpecs(): List<Spec> {
        fun spec(name: String, tier: Tier, seed: Long, ram: Int, daemons: List<Daemon>, script: Script) =
            Spec(name, tier, seed, daemons, lockedBuffer(tier, ram, daemons), false, script, lock = true)
        return listOf(
            spec("base_lock_solver", Tier.BASE, 21, 6, listOf(d("a", "1C", "55")), Script.SOLVER),
            spec("base_lock_walk", Tier.BASE, 22, 6, listOf(d("a", "BD", "E9"), d("g", "7A", "FF", effect = DaemonEffect.GHOST)), Script.WALK),
            spec(
                "hard_lock_solver", Tier.HARD, 23, 9,
                listOf(d("a", "55", "BD", "1C"), d("g", "E9", "7A", effect = DaemonEffect.GHOST)), Script.SOLVER
            ),
            spec("hard_lock_trap_first", Tier.HARD, 24, 7, listOf(d("a", "1C", "FF", "55")), Script.TRAP_FIRST),
            spec("nightmare_lock_solver", Tier.NIGHTMARE, 25, 8, listOf(d("a", "E9", "7A", "FF", "1C")), Script.SOLVER),
            spec("nightmare_lock_walk", Tier.NIGHTMARE, 26, 8, listOf(d("a", "7A", "FF", "BD")), Script.WALK),
        )
    }

    /** Цель шифр-замка: те же длины, что у приложения (BreachScreen.shardDecryptTarget); коды из алфавита детерминированно по зерну. */
    private fun decryptTarget(shardTier: Int, seed: Long): Daemon {
        val random = Random(seed)
        val codes = List(BreachConstants.shardDecryptTargetLength(shardTier)) { BreachSymbols.ALPHABET.random(random) }
        return Daemon("shard-decrypt", "Шифр-замок", codes)
    }

    // ── сборка файла ────────────────────────────────────────────────────────────────

    private fun cell(c: Pair<Int, Int>) = JsonArray(listOf(JsonPrimitive(c.first), JsonPrimitive(c.second)))
    private fun cells(c: Collection<Pair<Int, Int>>) = JsonArray(c.sortedWith(compareBy({ it.first }, { it.second })).map(::cell))
    private fun strs(l: Collection<String>) = JsonArray(l.map { JsonPrimitive(it) })
    private fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(mapOf(*pairs))

    private fun daemonJson(daemon: Daemon) = obj(
        "id" to JsonPrimitive(daemon.id), "name" to JsonPrimitive(daemon.name), "sequence" to strs(daemon.sequence),
        "tier" to JsonPrimitive(daemon.tier.level), "effect" to JsonPrimitive(daemon.effect.name),
    )

    private fun buildAttempt(spec: Spec): JsonObject {
        val params = BreachTierParams.forTier(spec.tier)
        val random = Random(spec.seed)
        val grid = generateGrid(params.gridSize, spec.daemons, random, if (spec.decrypt) null else params, if (spec.lock) params.lockLength else 0)
        // Шифр-замок шарда держит прежние таймеры 45/60/75 (BreachScreen.ShardDecryptFlow берёт cipherTimerSec).
        val timerSec = if (spec.decrypt) params.cipherTimerSec else params.timerSec
        var run = BreachRun(BreachAttemptState(grid, spec.daemons, spec.bufferSize), timerSec)
        val taps = when (spec.script) {
            Script.SOLVER -> BreachAutoSolver.solve(run.attempt)
            Script.WALK -> randomWalk(run, Random(spec.seed * 31 + 7))
            Script.TRAP_FIRST -> trapFirst(run, Random(spec.seed * 31 + 7))
            Script.FIRST_MATCH_THEN_TIMEOUT -> untilFirstMatch(run, BreachAutoSolver.solve(run.attempt))
            Script.NO_TAPS_TIMEOUT -> emptyList()
        }
        val steps = taps.map { tapCell ->
            val before = run.selectable
            val tap = run.tap(tapCell)
            run = tap.run
            JsonObject(
                mapOf(
                    "cell" to cell(tapCell),
                    "selectable_before" to cells(before),
                    "hit_trap" to JsonPrimitive(tap.hitTrap),
                    "matched_new" to JsonPrimitive(tap.matched),
                    "matched_ids" to strs(run.attempt.matchedDaemonIds.sorted()),
                    "buffer_codes" to strs(run.attempt.bufferCodes),
                    "is_full" to JsonPrimitive(run.attempt.isFull),
                    "selectable_after" to cells(run.selectable),
                ) + (if (spec.lock) mapOf("lock_opened" to JsonPrimitive(run.attempt.lockOpened)) else emptyMap())
            )
        }
        val startSelectable = BreachRun(BreachAttemptState(grid, spec.daemons, spec.bufferSize), timerSec).selectable
        val resolved = run.resolve()
        val result = resolved.result!!
        // Поля замка — только у спецификаций с замком: у старых спецификаций файл не меняется (порт читает их как «без замка»).
        val lockFields: Map<String, JsonElement> = if (!spec.lock) emptyMap() else mapOf(
            "lock" to strs(grid.lock),
            "lock_opened" to JsonPrimitive(result.lockOpened),
            "matched_before_lock" to strs(result.matchedBeforeLock.sorted()),
        )
        return JsonObject(
            mapOf(
                "name" to JsonPrimitive(spec.name),
                "mode" to JsonPrimitive(if (spec.decrypt) "decrypt" else "breach"),
                "tier" to JsonPrimitive(spec.tier.name),
                "grid_size" to JsonPrimitive(grid.size),
                "timer_sec" to JsonPrimitive(timerSec),
                "buffer_size" to JsonPrimitive(spec.bufferSize),
                "daemons" to JsonArray(spec.daemons.map(::daemonJson)),
                "cells" to JsonArray(grid.cells.map(::strs)),
                "trap_cells" to cells(grid.trapCells),
                "start_selectable" to cells(startSelectable),
                "steps" to JsonArray(steps),
                "outcome" to JsonPrimitive(result.outcome.name),
                "matched_ids" to strs(result.matchedIds.sorted()),
                "selectable_after_resolve" to cells(resolved.selectable),
            ) + lockFields
        )
    }

    /** Случайная ходьба по доступным клеткам до полного буфера: ловушки попадаются как придётся. */
    private fun randomWalk(start: BreachRun, random: Random): List<Pair<Int, Int>> {
        var run = start
        val taps = mutableListOf<Pair<Int, Int>>()
        while (!run.attempt.isFull) {
            val options = run.selectable.toList()
            val pick = options[random.nextInt(options.size)]
            taps += pick
            run = run.tap(pick).run
        }
        return taps
    }

    /** Путь автосолвера, оборванный сразу после первого совпавшего демона (остальные не собраны) — исход PARTIAL по таймеру. */
    private fun untilFirstMatch(start: BreachRun, path: List<Pair<Int, Int>>): List<Pair<Int, Int>> {
        var run = start
        val taps = mutableListOf<Pair<Int, Int>>()
        for (cell in path) {
            taps += cell
            run = run.tap(cell).run
            if (run.attempt.matchedDaemonIds.isNotEmpty()) break
        }
        return taps
    }

    /** Если в доступных клетках есть ловушка — берём её сразу; дальше случайная ходьба. Ловит правило «ловушка рвёт цепочку». */
    private fun trapFirst(start: BreachRun, random: Random): List<Pair<Int, Int>> {
        var run = start
        val taps = mutableListOf<Pair<Int, Int>>()
        while (!run.attempt.isFull) {
            val options = run.selectable.toList()
            val pick = options.firstOrNull { it in run.attempt.grid.trapCells } ?: options[random.nextInt(options.size)]
            taps += pick
            run = run.tap(pick).run
        }
        return taps
    }

    private fun buildTimerCases(): JsonArray {
        val grid = generateGrid(5, listOf(d("a", "1C", "55")), Random(1))
        val attempt = BreachAttemptState(grid, listOf(d("a", "1C", "55")), 6)
        // 60 и 75 — таймеры шифр-замка шарда (cipherTimerSec), 90 и 150 — HARD и NIGHTMARE во Взломе 2.0.
        val timers = listOf(15, 20, 21, 30, 45, 60, 75, 90, 150)
        return JsonArray(
            timers.map { timer ->
                val events = (timer downTo 0).mapNotNull { left ->
                    BreachRun(attempt, timer, left).timeEvent?.let { obj("seconds_left" to JsonPrimitive(left), "event" to JsonPrimitive(it.name)) }
                }
                obj("timer_sec" to JsonPrimitive(timer), "events" to JsonArray(events))
            }
        )
    }

    private fun buildResolveCases(): JsonArray {
        data class Case(val buffer: List<String>, val daemons: List<Daemon>, val lock: List<String> = emptyList())
        val a = d("a", "1C", "55")
        val b = d("b", "55", "BD")
        // Случаи с замком (breach.md 2.2): поле `lock` есть только у них, у старых случаев его нет.
        val lock = listOf("1C", "55")
        val loot = d("e", "BD", "E9")
        val ghost = d("g", "BD", "E9", effect = DaemonEffect.GHOST)
        val miner = d("m", "E9", "7A", effect = DaemonEffect.MINER)
        val trap = BreachSymbols.TRAP_SENTINEL
        val lockCases = listOf(
            Case(listOf("1C", "55", "BD", "E9"), listOf(loot), lock),
            Case(listOf("BD", "E9", "1C", "55"), listOf(loot), lock),
            Case(listOf("BD", "E9", "1C", "55"), listOf(ghost), lock),
            Case(listOf("1C", trap, "55", "BD", "E9"), listOf(loot), lock),
            Case(listOf("1C", "55", "E9"), listOf(d("o", "55", "E9")), lock),
            Case(listOf("BD", "E9", "1C", "55", "BD", "E9"), listOf(loot), lock),
            Case(listOf("BD", "E9"), listOf(loot, ghost.copy(id = "g2")), lock),
            Case(listOf("BD", "E9", "1C", "55", "E9", "7A"), listOf(loot, miner), lock),
        )
        val cases = listOf(
            Case(listOf("BD", "1C", "55", "E9"), listOf(a)),
            Case(listOf("1C", "E9", "55"), listOf(a)),
            Case(listOf("55", "1C"), listOf(a)),
            Case(listOf("1C", "55", "BD"), listOf(a, b)),
            Case(listOf("1C", "55"), listOf(a, b)),
            Case(listOf("1C", BreachSymbols.DEAD_MARKER, "55"), listOf(a)),
            Case(emptyList(), listOf(a)),
            Case(listOf("1C"), listOf(d("empty"))),
        )
        return JsonArray(
            (cases + lockCases).map { c ->
                val lockField: Map<String, JsonElement> = if (c.lock.isEmpty()) emptyMap() else mapOf("lock" to strs(c.lock))
                JsonObject(
                    mapOf(
                        "buffer" to strs(c.buffer), "daemons" to JsonArray(c.daemons.map(::daemonJson)),
                        "matched" to strs(resolveDaemons(c.buffer, c.daemons, c.lock).sorted()),
                    ) + lockField
                )
            }
        )
    }

    private fun buildLinkRule() = JsonArray(
        (1..8).map { n -> obj("selected_count" to JsonPrimitive(n), "next" to JsonPrimitive(nextLinkDimension(n).name)) }
    )

    private fun build() = obj(
        "format" to JsonPrimitive(1),
        "note" to JsonPrimitive("Сгенерировано тестом BreachGoldenTest (UPDATE_NETRUN_JSON=1) из :rules. Руками не править."),
        "link_rule" to buildLinkRule(),
        "resolve_cases" to buildResolveCases(),
        "timer_cases" to buildTimerCases(),
        "attempts" to JsonArray(specs.map(::buildAttempt)),
    )

    // ── проигрыш файла ──────────────────────────────────────────────────────────────

    private fun readCells(e: JsonElement): List<Pair<Int, Int>> = e.jsonArray.map { it.jsonArray[0].jsonPrimitive.int to it.jsonArray[1].jsonPrimitive.int }
    private fun readStrs(e: JsonElement): List<String> = e.jsonArray.map { it.jsonPrimitive.content }
    private fun sorted(c: Collection<Pair<Int, Int>>) = c.sortedWith(compareBy({ it.first }, { it.second }))
    private fun readDaemon(e: JsonElement): Daemon {
        val o = e.jsonObject
        return Daemon(
            o.getValue("id").jsonPrimitive.content, o.getValue("name").jsonPrimitive.content, readStrs(o.getValue("sequence")),
            Tier.fromLevel(o.getValue("tier").jsonPrimitive.int), DaemonEffect.valueOf(o.getValue("effect").jsonPrimitive.content),
        )
    }

    @Test
    fun `golden file replays on the rules`() {
        val file = NetrunJsonFiles.load("netrun/tests/fixtures/breach_golden.json", build()).jsonObject

        file.getValue("link_rule").jsonArray.forEach {
            val o = it.jsonObject
            assertEquals(o.getValue("next").jsonPrimitive.content, nextLinkDimension(o.getValue("selected_count").jsonPrimitive.int).name)
        }
        file.getValue("resolve_cases").jsonArray.forEach {
            val o = it.jsonObject
            val daemons = o.getValue("daemons").jsonArray.map(::readDaemon)
            val lock = o["lock"]?.let(::readStrs) ?: emptyList()
            assertEquals(readStrs(o.getValue("matched")), resolveDaemons(readStrs(o.getValue("buffer")), daemons, lock).sorted())
        }
        file.getValue("timer_cases").jsonArray.forEach {
            val o = it.jsonObject
            val timer = o.getValue("timer_sec").jsonPrimitive.int
            val attempt = BreachAttemptState(generateGrid(5, listOf(d("a", "1C", "55")), Random(1)), listOf(d("a", "1C", "55")), 6)
            val expected = o.getValue("events").jsonArray.associate { e -> e.jsonObject.getValue("seconds_left").jsonPrimitive.int to e.jsonObject.getValue("event").jsonPrimitive.content }
            val actual = (timer downTo 0).mapNotNull { left -> BreachRun(attempt, timer, left).timeEvent?.let { ev -> left to ev.name } }.toMap()
            assertEquals("timer $timer", expected, actual)
        }
        file.getValue("attempts").jsonArray.forEach { replayAttempt(it.jsonObject) }
        assertEquals(specs.map { it.name }, file.getValue("attempts").jsonArray.map { it.jsonObject.getValue("name").jsonPrimitive.content })
    }

    private fun replayAttempt(o: JsonObject) {
        val name = o.getValue("name").jsonPrimitive.content
        val size = o.getValue("grid_size").jsonPrimitive.int
        val cells = o.getValue("cells").jsonArray.map(::readStrs)
        val lock = o["lock"]?.let(::readStrs) ?: emptyList()
        val grid = BreachGrid(size, cells, readCells(o.getValue("trap_cells")).toSet(), lock)
        val daemons = o.getValue("daemons").jsonArray.map(::readDaemon)
        var run = BreachRun(BreachAttemptState(grid, daemons, o.getValue("buffer_size").jsonPrimitive.int), o.getValue("timer_sec").jsonPrimitive.int)
        assertEquals("$name: start", readCells(o.getValue("start_selectable")), sorted(run.selectable))
        o.getValue("steps").jsonArray.forEachIndexed { i, s ->
            val step = s.jsonObject
            val at = "$name step $i"
            assertEquals("$at selectable_before", readCells(step.getValue("selectable_before")), sorted(run.selectable))
            val tap = run.tap(readCells(JsonArray(listOf(step.getValue("cell")))).single())
            run = tap.run
            assertEquals("$at hit_trap", step.getValue("hit_trap").jsonPrimitive.content.toBoolean(), tap.hitTrap)
            assertEquals("$at matched_new", step.getValue("matched_new").jsonPrimitive.content.toBoolean(), tap.matched)
            assertEquals("$at matched_ids", readStrs(step.getValue("matched_ids")), run.attempt.matchedDaemonIds.sorted())
            assertEquals("$at buffer_codes", readStrs(step.getValue("buffer_codes")), run.attempt.bufferCodes)
            assertEquals("$at is_full", step.getValue("is_full").jsonPrimitive.content.toBoolean(), run.attempt.isFull)
            assertEquals("$at selectable_after", readCells(step.getValue("selectable_after")), sorted(run.selectable))
            step["lock_opened"]?.let { assertEquals("$at lock_opened", it.jsonPrimitive.content.toBoolean(), run.attempt.lockOpened) }
        }
        val resolved = run.resolve()
        val result = resolved.result!!
        o["lock_opened"]?.let { assertEquals("$name lock_opened", it.jsonPrimitive.content.toBoolean(), result.lockOpened) }
        o["matched_before_lock"]?.let { assertEquals("$name matched_before_lock", readStrs(it), result.matchedBeforeLock.sorted()) }
        assertEquals("$name outcome", o.getValue("outcome").jsonPrimitive.content, result.outcome.name)
        assertEquals("$name matched", readStrs(o.getValue("matched_ids")), result.matchedIds.sorted())
        assertEquals("$name after resolve", readCells(o.getValue("selectable_after_resolve")), sorted(resolved.selectable))
    }
}
