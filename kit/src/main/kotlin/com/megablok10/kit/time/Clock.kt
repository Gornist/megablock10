package com.megablok10.kit.time

/**
 * Источник «сейчас» в миллисекундах эпохи. Компоненты берут время отсюда, а не из System.currentTimeMillis(), чтобы тесты
 * могли вести часы вручную ([ManualClock]) — без ожиданий и без хрупких допусков.
 */
fun interface Clock {
    fun nowMs(): Long

    companion object {
        /** Настоящие часы устройства. */
        val System: Clock = Clock { java.lang.System.currentTimeMillis() }
    }
}

/** Часы для тестов: стоят, пока их не переведут. */
class ManualClock(@Volatile var now: Long = 0L) : Clock {
    override fun nowMs(): Long = now
    fun advance(ms: Long) { now += ms }
}
