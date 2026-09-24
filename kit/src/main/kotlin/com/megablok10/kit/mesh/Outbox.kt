package com.megablok10.kit.mesh

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.log.shortKey
import com.megablok10.kit.time.Clock
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Строка в очереди на отправку игроку [toPubKeyB64] и её график повторов. */
data class OutboxEntry(
    val id: Long,
    val toPubKeyB64: String,
    val line: String,
    val createdAt: Long,
    val attempts: Int = 0,
    val nextAttemptAt: Long = 0,
)

/** Хранилище очереди — порт: приложение даёт свою реализацию (в Мегаблоке — таблица Room `outbox`), тесты — список в памяти. */
interface OutboxQueue {
    suspend fun insert(toPubKeyB64: String, line: String, createdAt: Long)

    /** Записи, которым пора (nextAttemptAt <= now), в порядке постановки. */
    suspend fun due(now: Long): List<OutboxEntry>
    suspend fun delete(id: Long)
    suspend fun reschedule(id: Long, attempts: Int, nextAttemptAt: Long)
    suspend fun deleteOlderThan(cutoff: Long): Int
    suspend fun count(): Int
}

/**
 * Когда повторять и когда сдаваться. Значения по умолчанию подобраны под Wi-Fi площадки (docs/network-spec.md, §7): пауза
 * после N неудачных попыток — 2, 4, 8, 15, 30 с, дальше раз в минуту; через 12 часов сообщение уже не имеет смысла в игре.
 */
class OutboxSchedule(private val backoffMs: LongArray = DEFAULT_BACKOFF_MS, val maxAgeMs: Long = DEFAULT_MAX_AGE_MS) {
    init { require(backoffMs.isNotEmpty()) { "нужна хотя бы одна пауза" } }

    fun nextDelayMs(attempts: Int): Long = backoffMs[attempts.coerceIn(0, backoffMs.lastIndex)]

    companion object {
        val DEFAULT_BACKOFF_MS = longArrayOf(2_000, 4_000, 8_000, 15_000, 30_000, 60_000)
        const val DEFAULT_MAX_AGE_MS = 12L * 60 * 60 * 1000
    }
}

/**
 * Очередь исходящих строк с повторами (store-and-forward): строка попадает сюда, если адресата не видно или отправка не
 * удалась, и уходит, как только он снова виден ([flush] зовут при изменении списка пиров и по таймеру). Неудачная попытка —
 * пауза по [schedule]; адресат не виден — попыткой не считается, ждём его появления; ушедшее и просроченное удаляется.
 *
 * Что можно ставить в очередь, решает приложение: повтор должен быть безопасен (идемпотентен на приёме). Строки, которые
 * нельзя доставить «потом, само» (например, карточку перевода, который отправитель ещё может отменить), в очередь не кладут.
 *
 * Параллельные [flush] не пересекаются. [tag] — тег в журнале (в Мегаблоке `OutboxStore`).
 */
class Outbox(
    private val queue: OutboxQueue,
    private val schedule: OutboxSchedule = OutboxSchedule(),
    private val clock: Clock = Clock.System,
    private val log: KitLog = NoopLog,
    private val tag: String = "Outbox",
    private val send: suspend (PeerInfo, String) -> Boolean,
) {
    private val lock = Mutex()

    suspend fun enqueue(toPubKeyB64: String, line: String) = queue.insert(toPubKeyB64, line, clock.nowMs())

    suspend fun pending(): Int = queue.count()

    /** Пробует отправить всё, что пора и чей адресат виден в [peers] (ключ — pubKeyB64). Возвращает, сколько строк ушло. */
    suspend fun flush(peers: Map<String, PeerInfo>, now: Long = clock.nowMs()): Int = lock.withLock {
        queue.deleteOlderThan(now - schedule.maxAgeMs)
        var sent = 0
        for (entry in queue.due(now)) {
            val peer = peers[entry.toPubKeyB64] ?: continue
            if (send(peer, entry.line)) {
                queue.delete(entry.id); sent++
                log.event(tag, "outbox.sent", "id" to entry.id, "to" to shortKey(entry.toPubKeyB64), "attempts" to entry.attempts, "ageMs" to (now - entry.createdAt))
            } else {
                val attempts = entry.attempts + 1
                val delay = schedule.nextDelayMs(attempts)
                log.warnEvent(tag, "outbox.retry", "id" to entry.id, "to" to shortKey(entry.toPubKeyB64), "attempts" to attempts, "nextInMs" to delay)
                queue.reschedule(entry.id, attempts, now + delay)
            }
        }
        if (sent > 0) log.event(tag, "outbox.flushed", "sent" to sent, "left" to queue.count())
        sent
    }
}
