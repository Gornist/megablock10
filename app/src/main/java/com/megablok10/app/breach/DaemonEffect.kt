package com.megablok10.app.breach

/**
 * Что делает демон при совпадении в результате взлома. EXTRACT_* сопоставляются
 * со слотами лута контейнера в DaemonRewards; остальные — нейтрализаторы
 * сигнала SEC (см. SecAlertStore) и модификаторы самой попытки (Jitter).
 */
enum class DaemonEffect {
    /** Извлекает один слот лута типа SHARD (своего тира или ниже) из контейнера. */
    EXTRACT_SHARD,
    /** Извлекает один слот лута типа DAEMON (своего тира или ниже) из контейнера. */
    EXTRACT_DAEMON,
    /** Убирает идентификатор взломщика из сигнала SEC этой попытки. */
    GHOST,
    /** Откладывает отправку сигнала SEC этой попытки ещё на 10 минут. */
    TIMESKEW,
    /** Сигнал SEC для этой попытки не отправляется вовсе. */
    BLACKOUT,
    /** +15 секунд к таймеру текущей попытки. */
    JITTER,
    /** Дешифратор: без демона с этим эффектом (тира не ниже тира шарда) мини-игра расшифровки шарда не запускается. */
    DECRYPT,
    /** Майнер: успешный взлом контейнера приносит дополнительные эдди (см. ContainerEddies.minerBonus). */
    MINER
}

fun DaemonEffect.label(): String = when (this) {
    DaemonEffect.EXTRACT_SHARD -> "извлекает шард из контейнера"
    DaemonEffect.EXTRACT_DAEMON -> "извлекает демона из контейнера"
    DaemonEffect.GHOST -> "убирает ваш ID из сигнала СБ"
    DaemonEffect.TIMESKEW -> "+10 мин к задержке сигнала СБ"
    DaemonEffect.BLACKOUT -> "сигнал СБ не отправляется"
    DaemonEffect.JITTER -> "+15 сек к таймеру попытки"
    DaemonEffect.DECRYPT -> "расшифровывает зашифрованные шарды"
    DaemonEffect.MINER -> "добывает эдди из взломанного узла"
}

/** "N ячеек/ячейка/ячейки" с русским склонением — используется как цена демона в буфере взлома. */
fun cellsLabel(count: Int): String {
    val mod100 = count % 100
    val mod10 = count % 10
    val word = when {
        mod100 in 11..14 -> "ячеек"
        mod10 == 1 -> "ячейка"
        mod10 in 2..4 -> "ячейки"
        else -> "ячеек"
    }
    return "$count $word"
}
