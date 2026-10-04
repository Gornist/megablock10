package com.megablok10.app.testing

import com.megablok10.app.presence.NsdScheduler
import com.megablok10.kit.time.ManualClock

/** Планировщик NSD на ручных часах: таймеры срабатывают только в [advance] — без ожиданий и допусков. */
class ManualNsdScheduler(private val clock: ManualClock = ManualClock()) : NsdScheduler {
    private val timers = mutableListOf<Pair<Long, () -> Unit>>()

    override fun after(delayMs: Long, block: () -> Unit): () -> Unit {
        val timer = (clock.now + delayMs) to block
        timers += timer
        return { timers.remove(timer) }
    }

    fun advance(ms: Long) {
        clock.advance(ms)
        timers.filter { it.first <= clock.now }.forEach { t -> if (timers.remove(t)) t.second() }
    }
}
