package com.megablok10.rules

object BreachTierParams {
    fun forTier(tier: Tier): BreachParams = when (tier) {
        Tier.BASE -> BreachParams(gridSize = 5, timerSec = 45, deadCellsRange = 0..0, corruptedCodesRange = 0..0)
        Tier.HARD -> BreachParams(gridSize = 6, timerSec = 60, deadCellsRange = 2..3, corruptedCodesRange = 0..0)
        Tier.NIGHTMARE -> BreachParams(gridSize = 7, timerSec = 75, deadCellsRange = 5..6, corruptedCodesRange = 2..3)
    }
}

/**
 * Параметры одной попытки, зависящие от тира контейнера — buffer size
 * отдельно, это Character.ramCapacity игрока, не свойство тира (см. Identity.kt).
 * *Range — сколько мёртвых клеток/порченых кодов на попытку; конкретное
 * число внутри диапазона перебрасывается заново при каждой генерации сетки.
 */
data class BreachParams(
    val gridSize: Int,
    val timerSec: Int,
    val deadCellsRange: IntRange,
    val corruptedCodesRange: IntRange
)
