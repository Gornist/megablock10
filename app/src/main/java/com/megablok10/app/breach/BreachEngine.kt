package com.megablok10.app.breach

import kotlin.random.Random

/** Одна программа взлома — цепочка кодов, которую нужно собрать в буфере подряд. */
data class Daemon(
    val id: String,
    val name: String,
    val sequence: List<String>,
    val reward: String = ""
)

data class BreachGrid(
    val size: Int,
    val cells: List<List<String>>
) {
    fun codeAt(cell: Pair<Int, Int>): String = cells[cell.first][cell.second]
}

object BreachSymbols {
    val ALPHABET = listOf("1C", "55", "BD", "E9", "7A", "FF")
}

/**
 * Строит гарантированно решаемую сетку: сначала прокладывает валидный путь
 * (по правилам [nextLinkDimension]/[candidatesFor], начиная с верхней строки)
 * длиной ровно на сумму кодов выбранных демонов, вписывает их коды подряд
 * вдоль этого пути, и только оставшиеся клетки заполняет случайно. Если
 * пройти этим путём точно, буфер по порядку соберёт все demon.sequence
 * одну за другой — то есть решение существует по построению.
 */
fun generateGrid(gridSize: Int, daemons: List<Daemon>, random: Random = Random.Default): BreachGrid {
    val solutionCodes = daemons.flatMap { it.sequence }
    require(solutionCodes.size <= gridSize * gridSize) {
        "Суммарная длина демонов (${solutionCodes.size}) больше числа клеток сетки (${gridSize * gridSize})"
    }

    val path = buildSolvablePath(gridSize, solutionCodes.size, random)
        ?: error("Не удалось построить решаемый путь для сетки $gridSize x $gridSize и цепочки длиной ${solutionCodes.size}")

    val cells = Array(gridSize) { arrayOfNulls<String>(gridSize) }
    path.forEachIndexed { index, (r, c) -> cells[r][c] = solutionCodes[index] }
    for (r in 0 until gridSize) {
        for (c in 0 until gridSize) {
            if (cells[r][c] == null) cells[r][c] = BreachSymbols.ALPHABET.random(random)
        }
    }
    return BreachGrid(gridSize, cells.map { row -> row.map { it!! } })
}

private fun buildSolvablePath(
    gridSize: Int,
    length: Int,
    random: Random,
    maxAttempts: Int = 500
): List<Pair<Int, Int>>? {
    repeat(maxAttempts) {
        tryBuildPath(gridSize, length, random)?.let { return it }
    }
    return null
}

private fun tryBuildPath(gridSize: Int, length: Int, random: Random): List<Pair<Int, Int>>? {
    val path = mutableListOf<Pair<Int, Int>>()
    val visited = HashSet<Pair<Int, Int>>()

    // Первый выбор — всегда из верхней строки, как в оригинале.
    val start = 0 to random.nextInt(gridSize)
    path += start
    visited += start

    while (path.size < length) {
        val dimension = nextLinkDimension(path.size)
        val candidates = candidatesFor(path.last(), dimension, gridSize, visited)
        if (candidates.isEmpty()) return null
        val next = candidates.random(random)
        path += next
        visited += next
    }
    return path
}

/** Демоны, чья последовательность встретилась в буфере подряд и по порядку. */
fun resolveDaemons(buffer: List<String>, daemons: List<Daemon>): Set<String> =
    daemons.filter { containsContiguous(buffer, it.sequence) }.map { it.id }.toSet()

private fun containsContiguous(buffer: List<String>, needle: List<String>): Boolean {
    if (needle.isEmpty() || needle.size > buffer.size) return false
    for (start in 0..buffer.size - needle.size) {
        if (buffer.subList(start, start + needle.size) == needle) return true
    }
    return false
}
