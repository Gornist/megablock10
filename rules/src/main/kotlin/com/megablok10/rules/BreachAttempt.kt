package com.megablok10.rules

/** Состояние одной попытки взлома: сетка + что игрок уже выбрал. */
data class BreachAttemptState(
    val grid: BreachGrid,
    val daemons: List<Daemon>,
    val bufferSize: Int,
    val selected: List<Pair<Int, Int>> = emptyList()
) {
    val bufferCodes: List<String> get() = selected.map(grid::codeAt)
    val isFull: Boolean get() = selected.size >= bufferSize

    /** То же, что bufferCodes, но клетки-ловушки (grid.trapCells) заменены на TRAP_SENTINEL — не могут войти ни в один матч демона. */
    val matchCodes: List<String>
        get() = selected.map { cell -> if (cell in grid.trapCells) BreachSymbols.TRAP_SENTINEL else grid.codeAt(cell) }

    /** Замок хранилища этой попытки (пуст — без замка, правила как раньше). */
    val lock: List<String> get() = grid.lock

    /** Замок вскрыт: его цепочка целиком совпала в буфере (ловушка рвёт её, как любую). Без замка — всегда `false`. */
    val lockOpened: Boolean get() = lock.isNotEmpty() && lockOpenedAt(matchCodes, lock) != null

    /** Засчитанные демоны — с правилом замка (breach.md 2.2): добыча только после вскрытия, остальные где угодно. */
    val matchedDaemonIds: Set<String> get() = resolveDaemons(matchCodes, daemons, lock)

    /** Совпали бы без замка, но добыча легла до вскрытия (или замок так и не вскрыт) — не засчитаны. Без замка — пусто. */
    val matchedBeforeLockIds: Set<String>
        get() = if (lock.isEmpty()) emptySet() else resolveDaemons(matchCodes, daemons) - matchedDaemonIds

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

/**
 * Итог попытки (breach.md 2.6): SUCCESS — засчитаны все выбранные демоны (замок — не демон и в счёт не идёт), PARTIAL — хотя бы
 * один, FAIL — ни одного. [matchedIds] — уже засчитанные по правилу замка. [lockOpened] и [matchedBeforeLock] — для строк итога
 * «ЗАМОК: вскрыт / не вскрыт» и «совпал до вскрытия — не засчитан»; без замка — `false` и пусто. Оба — с умолчаниями, так что
 * конструктор из двух аргументов (Мост считает `BreachResult(...).outcome`) остался прежним.
 */
data class BreachResult(
    val allDaemons: List<Daemon>,
    val matchedIds: Set<String>,
    val lockOpened: Boolean = false,
    val matchedBeforeLock: Set<String> = emptySet()
) {
    val outcome: BreachOutcome
        get() = when {
            allDaemons.isNotEmpty() && matchedIds.size == allDaemons.size -> BreachOutcome.SUCCESS
            matchedIds.isNotEmpty() -> BreachOutcome.PARTIAL
            else -> BreachOutcome.FAIL
        }
}
