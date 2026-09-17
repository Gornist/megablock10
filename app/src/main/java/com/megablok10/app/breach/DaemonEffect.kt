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
    JITTER
}

fun DaemonEffect.label(): String = when (this) {
    DaemonEffect.EXTRACT_SHARD -> "извлекает шард из контейнера"
    DaemonEffect.EXTRACT_DAEMON -> "извлекает демона из контейнера"
    DaemonEffect.GHOST -> "убирает ваш ID из сигнала СБ"
    DaemonEffect.TIMESKEW -> "+10 мин к задержке сигнала СБ"
    DaemonEffect.BLACKOUT -> "сигнал СБ не отправляется"
    DaemonEffect.JITTER -> "+15 сек к таймеру попытки"
}
