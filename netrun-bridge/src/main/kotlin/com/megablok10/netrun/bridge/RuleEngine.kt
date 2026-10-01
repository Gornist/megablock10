package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Правила Моста (`docs/netrun.md`, «Устройство Моста»): маленькие обработчики «на изменение документа типа X» и «по таймеру».
 *
 * Всё идёт в одном потоке: [tick] разбирает очередь изменений и запускает созревшие таймеры. Слушатель [DocStore] только
 * кладёт изменения в очередь (он вызывается под замком хранилища и писать оттуда нельзя). Время — внедряемые [clock] и
 * ручной [tick], поэтому тесты не ждут. Боевой запуск — [start], он зовёт [tick] по таймеру.
 *
 * Правило пишет документы только через [RuleContext.update]/[RuleContext.create], а те проверяют [WriteGuard.checkValues]:
 * поля ценностей правилу недоступны (только операции B3). Исключение в правиле не роняет Мост: оно пишется в [log],
 * считается в [failures], а запись правила откатывается целиком.
 */
class RuleEngine(
    private val store: DocStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val log: (String) -> Unit = { System.err.println(it) },
    /** Сколько изменений разобрать за один [tick]: защита от правил, будящих друг друга бесконечно. */
    private val cascadeLimit: Int = 1000,
) : AutoCloseable {
    private class ChangeRule(val name: String, val type: String, val handler: (RuleContext, Change) -> Unit)
    private class TimerRule(
        val name: String,
        val settingKey: String,
        val defaultS: Long,
        val handler: (RuleContext) -> Unit,
    ) {
        var lastRun: Long? = null
    }

    private val changeRules = ArrayList<ChangeRule>()
    private val timerRules = ArrayList<TimerRule>()
    private val queue = ConcurrentLinkedQueue<Change>()
    private var executor: ScheduledExecutorService? = null
    private val failureCounts = HashMap<String, Long>()

    /** Последняя ошибка правил для дашборда и отладки (или null). */
    @Volatile var lastError: String? = null
        private set

    init {
        store.addListener { queue.addAll(it) }
    }

    /** Общее число сбоев правил с начала работы. */
    val failures: Long @Synchronized get() = failureCounts.values.sum()

    @Synchronized
    fun failuresOf(rule: String): Long = failureCounts[rule] ?: 0L

    /** Правило «на изменение документа типа [type]» (создание, правка, удаление; смотреть [Change.deleted]). */
    @Synchronized
    fun onChange(name: String, type: String, handler: (RuleContext, Change) -> Unit) {
        changeRules.add(ChangeRule(name, type, handler))
    }

    /**
     * Правило «по таймеру»: период в секундах берётся из `settings/global` по ключу [settingKey] при каждом запуске
     * (мастер правит число на ходу), а если ключа нет — [defaultS]. Первый запуск — сразу на первом [tick].
     */
    @Synchronized
    fun every(name: String, settingKey: String, defaultS: Long, handler: (RuleContext) -> Unit) {
        timerRules.add(TimerRule(name, settingKey, defaultS, handler))
    }

    /** Один проход: изменения, потом таймеры. Тесты зовут сами, боевой Мост — через [start]. */
    @Synchronized
    fun tick() {
        val ctx = RuleContext(store, clock())
        var budget = cascadeLimit
        var c = queue.poll()
        while (c != null) {
            if (budget-- <= 0) {
                queue.clear()
                fail("engine", "каскад правил длиннее $cascadeLimit изменений за проход, остаток отброшен")
                break
            }
            for (r in changeRules) if (r.type == c.doc.type) guarded(r.name) { r.handler(ctx, c!!) }
            c = queue.poll()
        }
        val now = clock()
        for (r in timerRules) {
            val period = ctx.setting(r.settingKey, r.defaultS).coerceAtLeast(1L) * 1000
            val last = r.lastRun
            if (last == null || now - last >= period) {
                r.lastRun = now
                guarded(r.name) { r.handler(RuleContext(store, now)) }
            }
        }
    }

    /** Боевой запуск: [tick] каждые [periodMs] в отдельном потоке-демоне. */
    @Synchronized
    fun start(periodMs: Long = 250) {
        if (executor != null) return
        val ex = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "netrun-rules").apply { isDaemon = true } }
        ex.scheduleWithFixedDelay(
            { try { tick() } catch (e: Exception) { fail("engine", e.toString()) } },
            0, periodMs, TimeUnit.MILLISECONDS,
        )
        executor = ex
    }

    @Synchronized
    override fun close() {
        executor?.shutdownNow()
        executor = null
    }

    private inline fun guarded(rule: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            fail(rule, e.toString())
        }
    }

    private fun fail(rule: String, what: String) {
        failureCounts[rule] = (failureCounts[rule] ?: 0L) + 1
        val msg = "rule.failed rule=$rule error=$what"
        lastError = msg
        runCatching { log(msg) }
    }
}

/** То, что видит правило: чтение, числа из настроек и записи через проверку ценностей. */
class RuleContext internal constructor(private val store: DocStore, val now: Long) {
    fun get(type: String, id: String): Doc? = store.get(type, id)
    fun list(type: String): List<Doc> = store.list(type)

    /** Число из `settings/global` (протокол, раздел 4); нет документа, поля или оно не число — [default]. */
    fun setting(key: String, default: Long): Long =
        (store.get("settings", "global")?.data?.get(key) as? JsonPrimitive)?.longOrNull ?: default

    /**
     * Меняет данные существующего документа функцией [change] одной транзакцией. Равные данные не пишутся (нет лишнего
     * `ver`). Поле ценности — [StoreException] `value_field`, и правило считается сбойным. Возвращает итоговый документ,
     * null — документа нет.
     */
    fun update(type: String, id: String, change: (JsonObject) -> JsonObject): Doc? =
        store.transaction { tx ->
            val cur = tx.get(type, id) ?: return@transaction null
            val next = change(cur.data)
            if (next == cur.data) return@transaction cur
            WriteGuard.checkValues(type, cur, next)
            tx.put(type, id, cur.ver, next)
        }

    /** Создаёт документ, если его нет; иначе возвращает null. Ценности создавать нельзя. */
    fun create(type: String, id: String, data: JsonObject): Doc? =
        store.transaction { tx ->
            if (tx.get(type, id) != null) return@transaction null
            WriteGuard.checkValues(type, null, data)
            tx.put(type, id, 0, data)
        }
}

/**
 * Правило-пример: терминал, который молчит дольше `settings.terminal_silent_s` (по умолчанию 30 с), получает
 * `silent: true`; когда кто-то другой тронет документ — флаг снимается. Время молчания — `updated` документа, а свою
 * запись правило узнаёт по версии, чтобы не принять её за признак жизни терминала.
 */
class TerminalSilentRule(private val engine: RuleEngine) {
    private val ownVer = HashMap<String, Long>()

    fun register() {
        engine.every("terminal_silent", "terminal_silent_s", 30) { ctx ->
            val limit = ctx.setting("terminal_silent_s", 30) * 1000
            for (t in ctx.list("terminal")) {
                if (isSilent(t) || ctx.now - t.updated <= limit) continue
                ctx.update("terminal", t.id) { JsonObject(it + ("silent" to JsonPrimitive(true))) }?.let { ownVer[t.id] = it.ver }
            }
        }
        engine.onChange("terminal_alive", "terminal") { ctx, c ->
            if (c.deleted) {
                ownVer.remove(c.doc.id)
                return@onChange
            }
            if (ownVer[c.doc.id] == c.doc.ver || !isSilent(c.doc)) return@onChange
            ctx.update("terminal", c.doc.id) { JsonObject(it + ("silent" to JsonPrimitive(false))) }?.let { ownVer[c.doc.id] = it.ver }
        }
    }

    private fun isSilent(d: Doc) = (d.data["silent"] as? JsonPrimitive)?.content == "true"
}
