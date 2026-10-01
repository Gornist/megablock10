package com.megablok10.netrun.bridge

import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** Найденное расхождение: [kind] и [subject] определяют документ тревоги (одна тревога на расхождение, не на проход). */
data class Violation(val kind: String, val subject: String, val msg: String, val items: List<String>)

/**
 * Аудитор ценностей (протокол, раздел 6): раз в N секунд проверяет, что у каждого предмета ровно один владелец из таблицы,
 * `deck:<s>` — только у не закрытой сессии, `deck.items` совпадает с предметами `owner: deck:<s>`, `outbox` не бывает без
 * исходящей карточки, а эдди не уходят в минус и не застревают в закрытой сессии. Расхождение — документ `alert`
 * (`al_a_<хеш>`, повторный проход тревогу не дублирует; мастер снимает её удалением, и если расхождение живо — она вернётся).
 * Аудитор ценности **не чинит** и ничего, кроме `alert`, не пишет.
 */
class Auditor(
    private val store: DocStore,
    private val clock: () -> Long = System::currentTimeMillis,
) : AutoCloseable {
    private var pool: ScheduledExecutorService? = null

    /** Сбоев прохода подряд (0 после успешного). */
    @Volatile var consecutiveFailures: Int = 0
        private set

    /** Время последнего успешного прохода, 0 — ещё не было. */
    @Volatile var lastSuccessAt: Long = 0L
        private set

    /** Чистая проверка без записи. */
    fun check(): List<Violation> {
        // Один снимок на проход: отдельные list() видели бы разные моменты, и run.finish между ними давал бы ложные тревоги.
        val all = store.snapshot(TYPES).second.groupBy { it.type }
        fun of(t: String) = all[t].orEmpty()
        val items = of(ValueOps.ITEM)
        val sessions = of(ValueOps.SESSION).associateBy { it.id }
        val nodeDocs = of(ValueOps.NODE)
        val nodes = nodeDocs.map { it.id }.toSet()
        val decks = of(ValueOps.DECK).associateBy { it.id }
        val out = ArrayList<Violation>()
        for (it in items) checkItem(it, sessions, nodes, out)
        checkDecks(items, sessions, decks, out)
        checkEddies(sessions, nodeDocs, of(ValueOps.PAYOUT), out)
        return out
    }

    private fun checkItem(item: Doc, sessions: Map<String, Doc>, nodes: Set<String>, out: MutableList<Violation>) {
        val owner = VJ.str(item.data, "owner")
        val kind = owner?.substringBefore(':')
        val ref = owner?.substringAfter(':', "") ?: ""
        val problem: String? = when {
            owner == null || ref.isEmpty() -> "нет владельца или он пуст"
            kind == "inbox" || kind == "phone" -> null
            kind == "deck" -> if (isOpen(sessions[ref])) null else "владелец $owner, но сессия закрыта или её нет"
            kind == "burned" -> if (sessions.containsKey(ref)) null else "сгорел в несуществующей сессии $ref"
            kind == "node" -> if (ref in nodes) null else "лежит в несуществующем узле $ref"
            kind == "outbox" -> outboxProblem(item)
            else -> "неизвестный владелец $owner"
        }
        if (problem != null) out.add(Violation("item_owner", item.id, "${item.id}: $problem", listOf(item.id)))
    }

    private fun isOpen(s: Doc?): Boolean = s != null && VJ.str(s.data, "state") != "closed"

    private fun outboxProblem(item: Doc): String? = when {
        VJ.str(item.data, "out_transfer").isNullOrEmpty() -> "outbox без исходящей карточки"
        VJ.str(item.data, "handover") !in setOf("PENDING", "DELIVERED") -> "outbox с неверным состоянием выдачи"
        else -> null
    }

    private fun checkDecks(items: List<Doc>, sessions: Map<String, Doc>, decks: Map<String, Doc>, out: MutableList<Violation>) {
        val owned = items.filter { VJ.str(it.data, "owner")?.startsWith("deck:") == true }
            .groupBy({ VJ.str(it.data, "owner")!!.removePrefix("deck:") }, { it.id })
        for (sid in (owned.keys + decks.keys).toSortedSet()) {
            val real = owned[sid].orEmpty().toSet()
            val deck = decks[sid]
            val listed = deck?.let { VJ.list(it.data, "items") }.orEmpty()
            if (deck == null && real.isNotEmpty()) {
                out.add(Violation("deck_items", sid, "у сессии $sid нет деки, а предметы с её владельцем есть", real.sorted()))
            } else if (deck != null && (listed.toSet() != real || listed.size != real.size)) {
                val diff = (listed.toSet() - real) + (real - listed.toSet())
                out.add(Violation("deck_items", sid, "deck.items сессии $sid не совпадает с предметами-владельцами", diff.sorted()))
            }
            val s = sessions[sid]
            val closed = s != null && !isOpen(s)
            if (listed.isNotEmpty() && closed) {
                out.add(Violation("deck_items", "closed:$sid", "в деке закрытой сессии $sid остались предметы", listed.sorted()))
            }
        }
    }

    private fun checkEddies(sessions: Map<String, Doc>, nodes: List<Doc>, payouts: List<Doc>, out: MutableList<Violation>) {
        for (n in nodes) {
            if (VJ.lng(n.data, "eddies") < 0) out.add(Violation("eddies", "node:${n.id}", "в узле ${n.id} эдди ушли в минус", emptyList()))
        }
        for (s in sessions.values) {
            val loot = VJ.lng(s.data, "loot_eddies")
            if (loot < 0) out.add(Violation("eddies", "loot:${s.id}", "у сессии ${s.id} добыча эдди отрицательна", emptyList()))
            if (loot > 0 && VJ.str(s.data, "state") == "closed") {
                out.add(Violation("eddies", "stuck:${s.id}", "закрытая сессия ${s.id} держит $loot эдди", emptyList()))
            }
        }
        for (p in payouts) {
            if (VJ.lng(p.data, "eddies") <= 0) out.add(Violation("eddies", "payout:${p.id}", "выплата ${p.id} не положительна", emptyList()))
        }
    }

    /** Проверка и запись тревог одной транзакцией; возвращает все найденные расхождения (в том числе уже с тревогой). */
    fun run(): List<Violation> {
        val found = check()
        if (found.isEmpty()) return found
        store.transaction { tx ->
            for (v in found) {
                val id = "al_a_" + VJ.sha256Hex("${v.kind}|${v.subject}").take(12)
                if (tx.get(ValueOps.ALERT, id) == null) {
                    tx.put(
                        ValueOps.ALERT, id, 0,
                        VJ.obj("kind" to VJ.p("auditor_${v.kind}"), "msg" to VJ.p(v.msg), "items" to VJ.arr(v.items)),
                    )
                }
            }
        }
        return found
    }

    /** Запустить проход каждые [periodSeconds] с (по умолчанию из `settings/global.auditor_period_s`, иначе 60). */
    @Synchronized
    fun start(periodSeconds: Long = periodFromSettings()) {
        check(pool == null) { "аудитор уже запущен" }
        val p = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "netrun-auditor").apply { isDaemon = true } }
        p.scheduleWithFixedDelay({ tick() }, periodSeconds, periodSeconds, TimeUnit.SECONDS)
        pool = p
    }

    /**
     * Один проход по таймеру. Исключение не должно убить расписание (иначе `scheduleWithFixedDelay` отменит проходы),
     * поэтому оно ловится, но не теряется: в stderr, в [consecutiveFailures], а после N подряд
     * (`settings/global.auditor_fail_alert_after`, по умолчанию 3) — тревога «аудитор не работает».
     */
    @Suppress("TooGenericExceptionCaught")
    internal fun tick(action: () -> Unit = { run() }) {
        try {
            action()
            consecutiveFailures = 0
            lastSuccessAt = clock()
        } catch (e: Exception) {
            val n = ++consecutiveFailures
            // TODO: писать в журнал Моста, когда он появится; пока в модуле журнала нет.
            System.err.println("[netrun-auditor] сбой прохода №$n подряд: $e")
            if (n >= failAlertAfter()) raiseDeadAlert(n, e)
        }
    }

    @Suppress("TooGenericExceptionCaught")
    private fun raiseDeadAlert(n: Int, cause: Exception) {
        try {
            store.transaction { tx ->
                if (tx.get(ValueOps.ALERT, DEAD_ALERT_ID) == null) {
                    val msg = "аудитор не работает: $n сбоев подряд, последний: $cause"
                    tx.put(ValueOps.ALERT, DEAD_ALERT_ID, 0, VJ.obj("kind" to VJ.p("auditor_dead"), "msg" to VJ.p(msg), "items" to VJ.arr(emptyList())))
                }
            }
        } catch (e: Exception) {
            System.err.println("[netrun-auditor] тревогу «аудитор не работает» записать не удалось: $e")
        }
    }

    private fun failAlertAfter(): Int =
        store.get(ValueOps.SETTINGS, "global")?.let { VJ.lng(it.data, "auditor_fail_alert_after") }?.takeIf { it > 0 }?.toInt() ?: DEFAULT_FAIL_ALERT

    private fun periodFromSettings(): Long =
        store.get(ValueOps.SETTINGS, "global")?.let { VJ.lng(it.data, "auditor_period_s") }?.takeIf { it > 0 } ?: DEFAULT_PERIOD_S

    @Synchronized
    override fun close() {
        pool?.shutdownNow()
        pool = null
    }

    private companion object {
        const val DEFAULT_PERIOD_S = 60L
        const val DEFAULT_FAIL_ALERT = 3
        const val DEAD_ALERT_ID = "al_a_auditor_dead"
        val TYPES = setOf(ValueOps.ITEM, ValueOps.SESSION, ValueOps.NODE, ValueOps.DECK, ValueOps.PAYOUT)
    }
}
