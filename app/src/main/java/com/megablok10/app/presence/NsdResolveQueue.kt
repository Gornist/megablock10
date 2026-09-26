package com.megablok10.app.presence

/**
 * Разрешение найденных NSD-сервисов (адрес и атрибуты) — по одному. На Android до 14 одновременный `resolveService` падает с
 * FAILURE_ALREADY_ACTIVE: пока к двум эмуляторам приходит по одному сервису, это не видно, а на площадке с десятками телефонов
 * поиск находит их пачкой — и большинство молча не разрешались бы. Здесь: очередь по имени сервиса (повторная находка того же —
 * не дубль), следующее — после ответа на текущее; «уже идёт» — повтор через [retryMs]; ответа нет [timeoutMs] — дальше.
 */
class NsdResolveQueue<S : Any>(
    private val name: (S) -> String,
    private val resolve: (item: S, token: Int) -> Unit,
    private val scheduler: NsdScheduler,
    private val timeoutMs: Long = 10_000,
    private val retryMs: Long = 1_000,
    private val maxAttempts: Int = 5,
) {
    private val queue = ArrayDeque<Pair<S, Int>>() // сервис и номер попытки
    private var active: Pair<S, Int>? = null
    private var token = 0
    private var cancelTimer: (() -> Unit)? = null

    @Synchronized fun add(item: S) {
        val n = name(item)
        if (active?.first?.let(name) == n || queue.any { name(it.first) == n }) return
        queue.addLast(item to 1)
        next()
    }

    /** Сервис пропал или поиск остановлен — не разрешать. */
    @Synchronized fun remove(serviceName: String) { queue.removeAll { name(it.first) == serviceName } }

    @Synchronized fun clear() {
        queue.clear(); active = null; cancelTimer?.invoke(); cancelTimer = null; token++
    }

    @Synchronized fun onResolved(token: Int) = finish(token)

    /** [busy] — FAILURE_ALREADY_ACTIVE (разрешение уже идёт где-то ещё): повторить позже, остальные ошибки — бросить. */
    @Synchronized fun onFailed(token: Int, busy: Boolean) {
        if (token != this.token) return
        val (item, attempt) = active ?: return
        if (busy && attempt < maxAttempts) {
            cancelTimer?.invoke()
            active = null
            // Повтор — в начало очереди, но через паузу: иначе тот же отказ сразу же.
            cancelTimer = scheduler.after(retryMs) { synchronized(this) { cancelTimer = null; queue.addFirst(item to attempt + 1); next() } }
            return
        }
        finish(token)
    }

    val pending: Int @Synchronized get() = queue.size + (if (active != null) 1 else 0)

    private fun finish(token: Int) {
        if (token != this.token) return
        cancelTimer?.invoke(); cancelTimer = null
        active = null
        next()
    }

    private fun next() {
        if (active != null || cancelTimer != null) return
        val current = queue.removeFirstOrNull() ?: return
        active = current
        val t = ++token
        cancelTimer = scheduler.after(timeoutMs) { synchronized(this) { cancelTimer = null; finish(t) } }
        resolve(current.first, t)
    }
}
