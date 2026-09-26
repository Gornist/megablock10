package com.megablok10.app.presence

/** Отложить [block] на [delayMs]; вернуть отмену. В приложении — корутина, в тестах — ручные часы. */
fun interface NsdScheduler {
    fun after(delayMs: Long, block: () -> Unit): () -> Unit
}

/**
 * Одна асинхронная операция NSD (регистрация сервиса или поиск) как «желаемое → фактическое» (docs/refactor-plan.md, B3): снаружи
 * только [want] (что должно быть: значение или null) и [restart] (пересоздать после смены сети), а операции Android ([Ops]) идут
 * строго по одной — следующая только после ответа на предыдущую.
 *
 * Зачем: NsdManager отвечает колбэком спустя сотни миллисекунд, а старый код снимал и ставил регистрацию, не дожидаясь ответа.
 * Незавершённая регистрация так терялась (e2e A4, wifi-bind 25.09: из 26 `nsd.start` лишь 3 `nsd.registered`), и устройство
 * переставало быть видно. Здесь снять ещё не завершённую нельзя по построению: пока идёт операция, новые желания только
 * запоминаются. Ответа нет дольше [opTimeoutMs] — операция считается потерянной (с попыткой снять, если это был запуск);
 * запуск не удался — повтор через [retryMs]. Ответы на устаревшие операции (по [token][Ops.start]) не учитываются.
 */
class NsdSlot<T : Any>(
    private val ops: Ops<T>,
    private val scheduler: NsdScheduler,
    private val opTimeoutMs: Long = 10_000,
    private val retryMs: Long = 5_000,
    private val onEvent: (String) -> Unit = {},
) {
    /** Операции Android. [token] — номер операции: вернуть его в [onStarted]/[onStartFailed]/[onStopped]. */
    interface Ops<T> {
        fun start(value: T, token: Int)
        fun stop(token: Int)
    }

    enum class Phase { IDLE, STARTING, UP, STOPPING }

    var phase = Phase.IDLE
        private set
    private var desired: T? = null
    private var current: T? = null
    private var token = 0
    private var restartPending = false
    private var cancelTimer: (() -> Unit)? = null

    @Synchronized fun want(value: T?) {
        desired = value
        if (value == null) restartPending = false
        reconcile()
    }

    /** Пересоздать то, что работает (смена сети). Идёт операция — пересоздание после её ответа. */
    @Synchronized fun restart() {
        if (desired == null) return
        restartPending = true
        reconcile()
    }

    @Synchronized fun onStarted(token: Int) {
        if (token != this.token || phase != Phase.STARTING) return
        settle(Phase.UP)
    }

    @Synchronized fun onStartFailed(token: Int) {
        if (token != this.token || phase != Phase.STARTING) return
        current = null
        settle(Phase.IDLE, reconcileNow = false)
        onEvent("start_failed")
        cancelTimer = scheduler.after(retryMs) { synchronized(this) { cancelTimer = null; reconcile() } }
    }

    /** И удачная остановка, и неудачная (Android: «уже не зарегистрирован») — операции больше нет. */
    @Synchronized fun onStopped(token: Int) {
        if (token != this.token || phase != Phase.STOPPING) return
        current = null
        settle(Phase.IDLE)
    }

    private fun settle(next: Phase, reconcileNow: Boolean = true) {
        cancelTimer?.invoke(); cancelTimer = null
        phase = next
        if (reconcileNow) reconcile()
    }

    private fun reconcile() {
        when (phase) {
            Phase.STARTING, Phase.STOPPING -> Unit // ждём ответа Android — ничего не трогаем
            Phase.UP -> if (desired != current || restartPending) {
                restartPending = false
                begin(Phase.STOPPING) { ops.stop(it) }
            }
            Phase.IDLE -> {
                val value = desired ?: return
                if (cancelTimer != null) return // ждём повтора после сбоя
                restartPending = false
                current = value
                begin(Phase.STARTING) { ops.start(value, it) }
            }
        }
    }

    private fun begin(next: Phase, op: (Int) -> Unit) {
        phase = next
        val t = ++token
        cancelTimer = scheduler.after(opTimeoutMs) { synchronized(this) { onTimeout(t) } }
        op(t)
    }

    private fun onTimeout(t: Int) {
        if (t != token) return
        cancelTimer = null
        onEvent("timeout_${phase.name.lowercase()}")
        // Запуск без ответа мог и пройти — снимаем на всякий случай (ответ на него уже устарел и не учтётся).
        if (phase == Phase.STARTING) ops.stop(t)
        current = null
        phase = Phase.IDLE
        reconcile()
    }
}
