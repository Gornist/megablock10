package com.megablok10.rules

/**
 * Перебор сетки для debug-автосолвера и тестов: находит цепочку клеток, на которой совпадает
 * как можно больше выбранных демонов (при равенстве — короче). Перебор с ограничением по
 * числу шагов, чтобы на больших сетках не зависнуть; при исчерпании бюджета возвращает лучшее найденное.
 *
 * Засчитывание идёт через [BreachAttemptState.matchedDaemonIds], значит солвер знает замок и порядок breach.md 2.2: добыча
 * считается только после вскрытия замка. Без замка порядок перебора прежний (путь не меняется). С замком перебор глубины
 * «замок + цепочки» не укладывается в бюджет, поэтому сначала [spellPath] ищет путь, выписывающий замок и цепочки демонов подряд
 * (точно и быстро — так устроены сетки генератора), а не найдя, идёт перебор с подсказкой [guidance].
 */
object BreachAutoSolver {
    private const val NODE_BUDGET = 200_000
    private const val SPELL_NODE_BUDGET = 200_000
    private const val MATCHED_WEIGHT = 1000
    private const val LOCK_WEIGHT = 500
    private const val MAX_ORDERED_DAEMONS = 5

    fun solve(start: BreachAttemptState): List<Pair<Int, Int>> {
        if (start.lock.isNotEmpty() && start.selected.isEmpty()) spellPath(start)?.let { return it }
        var best = start
        var bestScore = -1
        var nodes = 0

        fun score(s: BreachAttemptState) = s.matchedDaemonIds.size * 100 - s.selected.size

        fun dfs(s: BreachAttemptState) {
            if (nodes++ > NODE_BUDGET) return
            val sc = score(s)
            if (sc > bestScore) { best = s; bestScore = sc }
            if (s.matchedDaemonIds.size == s.daemons.size && s.daemons.isNotEmpty()) return
            val children = s.selectableCells().map { s.select(it) }
            val ordered = if (s.lock.isEmpty()) children else children.sortedByDescending(::guidance)
            for (child in ordered) {
                dfs(child)
                if (best.matchedDaemonIds.size == best.daemons.size && best.daemons.isNotEmpty()) return
            }
        }
        dfs(start)
        return best.selected
    }

    /**
     * Путь, на котором буфер читается как «замок, затем цепочки всех демонов подряд» — для каждого порядка демонов, пока не найдётся
     * путь, засчитывающий всех. Ловушки обходит. `null` — такого пути нет (или демонов слишком много для перебора порядков).
     */
    private fun spellPath(start: BreachAttemptState): List<Pair<Int, Int>>? {
        val daemons = start.daemons
        if (daemons.isEmpty() || daemons.size > MAX_ORDERED_DAEMONS || daemons.any { it.sequence.isEmpty() }) return null
        val budget = intArrayOf(SPELL_NODE_BUDGET) // общий на все порядки: перебор не должен виснуть на больших сетках
        return permutations(daemons).asSequence()
            .takeWhile { budget[0] > 0 }
            .map { order -> start.lock + order.flatMap { it.sequence } }
            .filter { target -> target.size <= start.bufferSize }
            .firstNotNullOfOrNull { target -> spellFrom(start, target, budget)?.selected }
    }

    private fun spellFrom(s: BreachAttemptState, target: List<String>, budget: IntArray): BreachAttemptState? {
        if (s.selected.size == target.size) return s.takeIf { it.matchedDaemonIds.size == it.daemons.size }
        if (--budget[0] <= 0) return null
        val want = target[s.selected.size]
        for (cell in s.selectableCells()) {
            if (cell in s.grid.trapCells || s.grid.codeAt(cell) != want) continue
            spellFrom(s.select(cell), target, budget)?.let { return it }
        }
        return null
    }

    private fun <T> permutations(items: List<T>): List<List<T>> =
        if (items.size <= 1) listOf(items)
        else items.indices.flatMap { i -> permutations(items.filterIndexed { j, _ -> j != i }).map { listOf(items[i]) + it } }

    /**
     * Насколько состояние ближе к решению: засчитанные демоны важнее вскрытого замка, он — важнее продвижения по цепочке,
     * которую нужно собрать следующей (длина самого длинного хвоста буфера, совпадающего с началом цепочки).
     */
    private fun guidance(s: BreachAttemptState): Int {
        val codes = s.matchCodes
        val matched = s.matchedDaemonIds
        val lockEnd = lockOpenedAt(codes, s.lock)
        val pending = s.daemons.filter { it.id !in matched }
        val targets = buildList {
            if (lockEnd == null) add(s.lock to codes)
            pending.forEach { daemon ->
                // Добыча до вскрытия замка не засчитается: её хвост считаем только по буферу после замка.
                if (!daemon.effect.isLoot) add(daemon.sequence to codes)
                else if (lockEnd != null) add(daemon.sequence to codes.drop(lockEnd))
            }
        }
        val progress = targets.maxOfOrNull { (chain, buffer) -> tailProgress(buffer, chain) } ?: 0
        return matched.size * MATCHED_WEIGHT + (if (lockEnd != null) LOCK_WEIGHT else 0) + progress
    }

    /** Длина самого длинного хвоста [buffer], который является началом [chain] (не всей цепочкой — целая уже совпала бы). */
    private fun tailProgress(buffer: List<String>, chain: List<String>): Int {
        for (len in minOf(chain.size - 1, buffer.size) downTo 1) {
            if (buffer.subList(buffer.size - len, buffer.size) == chain.subList(0, len)) return len
        }
        return 0
    }
}
