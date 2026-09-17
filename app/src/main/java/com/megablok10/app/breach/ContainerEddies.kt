package com.megablok10.app.breach

import kotlin.random.Random

/** Эдди за успешный/частичный взлом — суммы символические (реальный доход декера от продажи шардов, не от самого взлома), см. ревизию v9 §2. */
object ContainerEddies {
    fun roll(tier: Tier, random: Random = Random.Default): Long = when (tier) {
        Tier.BASE -> random.nextInt(1, 4)
        Tier.HARD -> random.nextInt(4, 7)
        Tier.NIGHTMARE -> random.nextInt(7, 11)
    }.toLong()
}
