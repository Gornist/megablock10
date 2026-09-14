package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Эти тесты — не про UI, а про то, что должно быть верно ДО любого UI:
 * сетка, которую строит generateGrid(), обязана быть решаема ровно теми же
 * правилами выбора клеток, что применяет экран (nextLinkDimension/
 * candidatesFor). Если генератор и UI когда-нибудь разъедутся (например,
 * кто-то поправит правило в одном месте и забудет про другое), это не
 * покажет себя как ошибка сборки — просто конкретные сетки станут нерешаемы
 * в игре. Полный перебор здесь ловит именно такой разъезд автоматически.
 */
class BreachEngineTest {

    @Test
    fun `generated grid is always solvable via the same selection rules the UI enforces`() {
        val daemons = MockBreach.daemons
        val totalLength = daemons.sumOf { it.sequence.size }

        repeat(150) { seed ->
            val grid = generateGrid(MockBreach.gridSize, daemons, Random(seed.toLong()))
            val solvable = hasSolutionPath(grid, totalLength, daemons)
            assertTrue(
                "Сетка (seed=$seed) не решается через правила выбора UI:\n${renderGrid(grid)}",
                solvable
            )
        }
    }

    @Test
    fun `resolveDaemons requires the sequence contiguous and in order`() {
        val daemon = Daemon("x", "X", listOf("1C", "55"))
        assertEquals(setOf("x"), resolveDaemons(listOf("BD", "1C", "55", "E9"), listOf(daemon)))
        assertEquals(emptySet<String>(), resolveDaemons(listOf("1C", "E9", "55"), listOf(daemon))) // разорвано
        assertEquals(emptySet<String>(), resolveDaemons(listOf("55", "1C"), listOf(daemon))) // не по порядку
    }

    @Test
    fun `partial buffer matches only daemons whose full sequence already fit`() {
        val a = Daemon("a", "A", listOf("1C", "55"))
        val b = Daemon("b", "B", listOf("BD", "E9", "7A"))
        val matched = resolveDaemons(listOf("1C", "55", "BD", "E9"), listOf(a, b))
        assertEquals(setOf("a"), matched)
    }

    @Test
    fun `selectable cells on a fresh attempt are exactly the top row`() {
        val grid = generateGrid(MockBreach.gridSize, MockBreach.daemons, Random(1))
        val state = BreachAttemptState(grid, MockBreach.daemons, MockBreach.ramCapacity)
        val expectedTopRow = (0 until grid.size).map { c -> 0 to c }.toSet()
        assertEquals(expectedTopRow, state.selectableCells())
    }

    @Test
    fun `select rejects a cell outside the current selectable set`() {
        val grid = generateGrid(MockBreach.gridSize, MockBreach.daemons, Random(2))
        val state = BreachAttemptState(grid, MockBreach.daemons, MockBreach.ramCapacity)
        val bottomRightNotInTopRow = (grid.size - 1) to (grid.size - 1)
        assertTrue(bottomRightNotInTopRow !in state.selectableCells())
        try {
            state.select(bottomRightNotInTopRow)
            assertTrue("ожидалось исключение — клетка вне правил выбора", false)
        } catch (_: IllegalArgumentException) {
            // ожидаемо
        }
    }

    /** Полный перебор допустимых по правилам UI путей длины [length]. */
    private fun hasSolutionPath(grid: BreachGrid, length: Int, daemons: List<Daemon>): Boolean {
        for (startCol in 0 until grid.size) {
            val start = 0 to startCol
            if (search(grid, listOf(start), setOf(start), length, daemons)) return true
        }
        return false
    }

    private fun search(
        grid: BreachGrid,
        path: List<Pair<Int, Int>>,
        visited: Set<Pair<Int, Int>>,
        targetLength: Int,
        daemons: List<Daemon>
    ): Boolean {
        if (path.size == targetLength) {
            return resolveDaemons(path.map(grid::codeAt), daemons).size == daemons.size
        }
        val dimension = nextLinkDimension(path.size)
        for (next in candidatesFor(path.last(), dimension, grid.size, visited)) {
            if (search(grid, path + next, visited + next, targetLength, daemons)) return true
        }
        return false
    }

    private fun renderGrid(grid: BreachGrid): String =
        grid.cells.joinToString("\n") { row -> row.joinToString(" ") }
}
