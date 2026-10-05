package com.megablok10.rules

import kotlin.random.Random

/** Эдди за успешный/частичный взлом — суммы символические (реальный доход декера от продажи шардов, не от самого взлома), см. ревизию v9 §2. */
object ContainerEddies {
    /** Добавка демона MINER к обычным эдди — по тиру контейнера. */
    fun minerBonus(tier: Tier): Long = when (tier) {
        Tier.BASE -> 15L
        Tier.HARD -> 30L
        Tier.NIGHTMARE -> 60L
    }

    /** Границы броска эдди за взлом (включительно) — по тиру контейнера. */
    fun rollRange(tier: Tier): IntRange = when (tier) {
        Tier.BASE -> 1..3
        Tier.HARD -> 4..6
        Tier.NIGHTMARE -> 7..10
    }

    fun roll(tier: Tier, random: Random = Random.Default): Long {
        val range = rollRange(tier)
        return random.nextInt(range.first, range.last + 1).toLong()
    }
}
