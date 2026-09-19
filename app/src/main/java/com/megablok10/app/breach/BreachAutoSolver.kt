package com.megablok10.app.breach

/**
 * Перебор сетки для debug-автосолвера и тестов: находит цепочку клеток, на которой совпадает
 * как можно больше выбранных демонов (при равенстве — короче). Перебор с ограничением по
 * числу шагов, чтобы на больших сетках не зависнуть; при исчерпании бюджета возвращает лучшее найденное.
 */
object BreachAutoSolver {
    private const val NODE_BUDGET = 200_000

    fun solve(start: BreachAttemptState): List<Pair<Int, Int>> {
        var best = start
        var bestScore = -1
        var nodes = 0

        fun score(s: BreachAttemptState) = s.matchedDaemonIds.size * 100 - s.selected.size

        fun dfs(s: BreachAttemptState) {
            if (nodes++ > NODE_BUDGET) return
            val sc = score(s)
            if (sc > bestScore) { best = s; bestScore = sc }
            if (s.matchedDaemonIds.size == s.daemons.size && s.daemons.isNotEmpty()) return
            for (cell in s.selectableCells()) {
                dfs(s.select(cell))
                if (best.matchedDaemonIds.size == best.daemons.size && best.daemons.isNotEmpty()) return
            }
        }
        dfs(start)
        return best.selected
    }
}
