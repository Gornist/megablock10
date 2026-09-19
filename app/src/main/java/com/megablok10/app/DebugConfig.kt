package com.megablok10.app

/**
 * Отладочные ручки для прогонов на эмуляторах (см. scripts/e2e/). Меняются только из
 * debug-only приёмника DebugQrReceiver, поэтому в release-сборке всегда остаются значениями
 * по умолчанию: часы идут в реальном времени, автосолвер выключен.
 */
object DebugConfig {
    /** Во сколько раз быстрее идут «игровые» часы: кулдаун контейнера, задержки/TTL/агрегация сигналов СБ. */
    @Volatile var clockSpeed: Double = 1.0

    /** Множитель таймера взлома: на медленном эмуляторе тапать сетку вручную не успеть. */
    @Volatile var breachTimerFactor: Double = 1.0

    /** Сетка решается сама, как только начался взлом. */
    @Volatile var autoSolve: Boolean = false

    /** >0 — автосолвер жмёт клетки по одной с этой паузой (для демо-записи), 0 — решает мгновенно. */
    @Volatile var autoSolveStepMs: Long = 0

    fun scaledMs(ms: Long): Long = if (clockSpeed == 1.0) ms else (ms / clockSpeed).toLong().coerceAtLeast(1)

    fun scaledTimerSec(sec: Int): Int = if (breachTimerFactor == 1.0) sec else (sec * breachTimerFactor).toInt().coerceAtLeast(1)
}
