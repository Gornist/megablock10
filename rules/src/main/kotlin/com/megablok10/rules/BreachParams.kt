package com.megablok10.rules

object BreachTierParams {
    fun forTier(tier: Tier): BreachParams = when (tier) {
        Tier.BASE -> BreachParams(
            gridSize = 5, timerSec = 45, deadCellsRange = 0..0, corruptedCodesRange = 0..0,
            lockLength = 1, bufferSlack = 2, cipherTimerSec = 45,
        )
        Tier.HARD -> BreachParams(
            gridSize = 6, timerSec = 90, deadCellsRange = 2..3, corruptedCodesRange = 1..2,
            lockLength = 2, bufferSlack = 1, cipherTimerSec = 60,
            failPenaltyLockStep = 1, failPenaltyTrapStep = 1, failPenaltyMaxSteps = 2, failPenaltyMinutes = 10,
        )
        Tier.NIGHTMARE -> BreachParams(
            gridSize = 7, timerSec = 150, deadCellsRange = 5..6, corruptedCodesRange = 3..4,
            lockLength = 3, bufferSlack = 0, cipherTimerSec = 75,
            failPenaltyLockStep = 1, failPenaltyTrapStep = 1, failPenaltyMaxSteps = 2, failPenaltyMinutes = 10,
        )
    }

    /**
     * Буфер попытки: наименьшее из RAM игрока и «замок + сумма длин выбранных демонов + запас тира» (breach.md 2.3).
     * [lockLength] — длина замка этой попытки (число тира плюс надбавка настороженности, если она есть: решает вызывающий).
     * [daemonsLen] — суммарная длина цепочек выбранных демонов.
     */
    fun bufferSize(ram: Int, lockLength: Int, daemonsLen: Int, tier: Tier): Int =
        minOf(ram, lockLength + daemonsLen + forTier(tier).bufferSlack)

    /** Дека влезает в RAM: «замок + выбранные» не больше RAM, иначе начать взлом нельзя (breach.md 2.3). */
    fun fitsRam(ram: Int, lockLength: Int, daemonsLen: Int): Boolean = lockLength + daemonsLen <= ram
}

/**
 * Параметры одной попытки, зависящие от тира контейнера — buffer size
 * отдельно, это Character.ramCapacity игрока, не свойство тира (см. Identity.kt).
 * *Range — сколько мёртвых клеток/порченых кодов (приманок) на попытку; конкретное
 * число внутри диапазона перебрасывается заново при каждой генерации сетки.
 *
 * Поля Взлома 2.0 (breach.md, раздел 3) — все с умолчаниями «как раньше», чтобы старые вызовы собирались без правок:
 * - [lockLength] — длина замка хранилища по тиру. Само по себе число ничего не меняет: замок в попытку вводит вызывающий
 *   (параметр `lock` у [generateGrid]), иначе экран получил бы замок без строки «ЗАМОК».
 * - [bufferSlack] — запас клеток буфера сверх «замок + демоны» (см. [BreachTierParams.bufferSize]).
 * - [cipherTimerSec] — таймер мини-взлома «шифр-замок шарда»: он остался прежним (45/60/75), хотя таймер взлома контейнера вырос.
 * - failPenalty* — цена провала (breach.md 2.7): шаг замка и приманок за один FAIL, потолок шагов, срок настороженности в минутах;
 *   [failPenaltyMinutes] = 0 — цены нет (BASE). Здесь только числа, хранит состояние вызывающий.
 */
data class BreachParams(
    val gridSize: Int,
    val timerSec: Int,
    val deadCellsRange: IntRange,
    val corruptedCodesRange: IntRange,
    val lockLength: Int = 0,
    val bufferSlack: Int = 0,
    val cipherTimerSec: Int = timerSec,
    val failPenaltyLockStep: Int = 0,
    val failPenaltyTrapStep: Int = 0,
    val failPenaltyMaxSteps: Int = 0,
    val failPenaltyMinutes: Int = 0
)
