package com.megablok10.rules

/**
 * Одна программа взлома — цепочка кодов, которую нужно собрать в буфере
 * подряд. Вес демона = sequence.size, отдельного поля под это нет. Награды
 * на демоне больше нет (см. ревизию v9) — что демон делает при совпадении,
 * определяет effect (см. DaemonEffect.kt); лут теперь на контейнере, не на
 * демоне, поэтому демон — многоразовый инструмент, а не билет на один раз.
 */
data class Daemon(
    val id: String,
    val name: String,
    val sequence: List<String>,
    val tier: Tier = Tier.BASE,
    val effect: DaemonEffect = DaemonEffect.EXTRACT_SHARD
)
