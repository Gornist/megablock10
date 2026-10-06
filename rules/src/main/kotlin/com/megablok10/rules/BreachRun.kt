package com.megablok10.rules

/** Что сделал тап: [hitTrap] — клетка-ловушка, [matched] — после тапа совпало больше демонов, чем до него. */
data class BreachTap(val run: BreachRun, val hitTrap: Boolean, val matched: Boolean)

/**
 * Ход одной попытки взлома без Android и Compose: набор клеток, оставшиеся секунды и итог. Неизменяемый — экран хранит его в одном
 * состоянии и заменяет результатом [tap]/[tick]/[resolve]; звук, хаптик и журнал остаются на экране.
 * [resolve] срабатывает один раз: итог уже есть — вернёт тот же [BreachRun], и экран видит, что завершать второй раз нечего.
 */
data class BreachRun(
    val attempt: BreachAttemptState,
    val timerSec: Int,
    val secondsLeft: Int = timerSec,
    val result: BreachResult? = null,
) {
    val isFinished: Boolean get() = result != null

    /** Таймер ещё идёт: время не вышло, буфер не полон, итога нет. */
    val isTicking: Boolean get() = secondsLeft > 0 && !attempt.isFull && result == null

    /** Последние 10 секунд до итога — шапка таймера мигает. */
    val isLowTime: Boolean get() = secondsLeft in 1..BreachConstants.LOW_TIME_SEC && result == null

    /** Последние 5 секунд — на каждом тике звучит предупреждение. */
    val isWarning: Boolean get() = secondsLeft in 1..BreachConstants.WARNING_SEC

    /** Реплика защиты на текущей секунде. Если половина окна и «10 секунд» совпали, остаётся LOW_TIME — он и был бы показан последним. */
    val timeEvent: IceEvent?
        get() = when {
            timerSec > BreachConstants.TIME_EVENTS_MIN_TIMER_SEC && secondsLeft == BreachConstants.LOW_TIME_SEC -> IceEvent.LOW_TIME
            timerSec > BreachConstants.TIME_EVENTS_MIN_TIMER_SEC && secondsLeft == timerSec / 2 -> IceEvent.HALF_TIME
            else -> null
        }

    /** Клетки, которые можно тапнуть сейчас; после итога — никакие. */
    val selectable: Set<Pair<Int, Int>> get() = if (result == null) attempt.selectableCells() else emptySet()

    fun tap(cell: Pair<Int, Int>): BreachTap {
        val next = attempt.select(cell)
        val hitTrap = cell in attempt.grid.trapCells
        val matched = next.matchedDaemonIds.size > attempt.matchedDaemonIds.size
        return BreachTap(copy(attempt = next), hitTrap, matched)
    }

    fun tick(): BreachRun = copy(secondsLeft = secondsLeft - 1)

    fun resolve(): BreachRun =
        if (result != null) this else copy(
            result = BreachResult(attempt.daemons, attempt.matchedDaemonIds, attempt.lockOpened, attempt.matchedBeforeLockIds)
        )
}
