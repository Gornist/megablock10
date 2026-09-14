package com.megablok10.app.breach

/** Состояние одной попытки взлома: сетка + что игрок уже выбрал. */
data class BreachAttemptState(
    val grid: BreachGrid,
    val daemons: List<Daemon>,
    val bufferSize: Int,
    val selected: List<Pair<Int, Int>> = emptyList()
) {
    val bufferCodes: List<String> get() = selected.map(grid::codeAt)
    val isFull: Boolean get() = selected.size >= bufferSize
    val matchedDaemonIds: Set<String> get() = resolveDaemons(bufferCodes, daemons)

    /**
     * Клетки, доступные для СЛЕДУЮЩЕГО тапа — используют то же самое правило
     * chередования, что и генератор сетки ([nextLinkDimension]/[candidatesFor]).
     * Если буфер уже полон — пусто (взлом завершён).
     */
    fun selectableCells(): Set<Pair<Int, Int>> {
        if (isFull) return emptySet()
        if (selected.isEmpty()) {
            return (0 until grid.size).map { c -> 0 to c }.toSet()
        }
        val dimension = nextLinkDimension(selected.size)
        return candidatesFor(selected.last(), dimension, grid.size, selected.toSet()).toSet()
    }

    fun select(cell: Pair<Int, Int>): BreachAttemptState {
        require(cell in selectableCells()) { "Клетка $cell недоступна для выбора на этом шаге" }
        return copy(selected = selected + cell)
    }
}

enum class BreachOutcome { SUCCESS, PARTIAL, FAIL }

data class BreachResult(val allDaemons: List<Daemon>, val matchedIds: Set<String>) {
    val outcome: BreachOutcome
        get() = when {
            allDaemons.isNotEmpty() && matchedIds.size == allDaemons.size -> BreachOutcome.SUCCESS
            matchedIds.isNotEmpty() -> BreachOutcome.PARTIAL
            else -> BreachOutcome.FAIL
        }
}
