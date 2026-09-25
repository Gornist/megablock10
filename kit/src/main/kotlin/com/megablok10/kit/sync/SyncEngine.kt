package com.megablok10.kit.sync

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.time.Clock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/** Куда слать: адрес мастерского сервера и общий секрет игры (null — сервер его не требует). */
data class CollectorEndpoint(val baseUrl: String, val secret: String?)

/**
 * Один обмен с сервером: наши записи, чей это телефон ([subjectKeyB64] — даже при пустом [records]: этим же запросом сервер
 * отдаёт правки мастера для этого ключа), подтверждения правок, применённых с прошлого ответа, отказы по правкам, которые
 * применить не удалось ([failures]), и heartbeat [presence].
 */
data class SyncRequest(
    val records: List<ChangeRecord>,
    val subjectKeyB64: String?,
    val ackIds: List<String>,
    val presence: Map<String, Any?>?,
    val failures: List<ApplyFailure> = emptyList(),
    /** id подтверждённой правки → последний seq телефона в момент её применения: сервер ставит правку в хронологию телефона. */
    val appliedAtSeq: Map<String, Long> = emptyMap(),
)

/**
 * Исход применения правки мастера на телефоне. Подтверждается серверу только [Applied]: неприменённая правка, подтверждённая
 * «для порядка», больше не пришла бы никогда и терялась молча.
 */
sealed interface MasterApply {
    data object Applied : MasterApply

    /**
     * Не применилась. [permanent] — повтор не поможет (поле, которого эта версия приложения не знает; значение не того вида):
     * сервер сразу перестаёт её слать и показывает мастеру. Иначе (сбой базы и т. п.) сервер пришлёт её снова и сдастся сам
     * после нескольких попыток.
     */
    data class Failed(val reason: String, val permanent: Boolean) : MasterApply
}

/** Правка мастера [id] не применилась на телефоне — уходит серверу следующим запросом вместо подтверждения. */
data class ApplyFailure(val id: String, val reason: String, val permanent: Boolean)

/**
 * Ответ сервера: что принято, что отбраковано (id → причина), правки мастера для этого телефона, адреса других игроков и
 * [knownSeq] — последний seq каждого затронутого игрока, который есть у сервера (по нему телефон замечает, что сервер потерял
 * уже подтверждённые записи, например после восстановления из резервной копии).
 */
data class SyncResponse(
    val accepted: Set<String>,
    val rejected: Map<String, String>,
    val pending: List<ChangeRecord>,
    val peers: List<PeerInfo> = emptyList(),
    val knownSeq: Map<String, Long> = emptyMap(),
)

/** Транспорт до сервера — порт (у Мегаблока — POST /api/changes через OkHttp). null — сеть или сервер недоступны. */
fun interface CollectorTransport {
    suspend fun exchange(endpoint: CollectorEndpoint, request: SyncRequest): SyncResponse?
}

/** Состояние очереди для heartbeat: дашборд видит телефон «на связи», но с застрявшей синхронизацией. */
data class QueueStats(val pendingCount: Int, val oldestPendingAgeMs: Long)

/** Что приложение делает с ответом сервера. Все методы необязательные. */
interface SyncHooks {
    /** Сервер подсказал адреса других игроков (запасное обнаружение). Зовётся, только если у устройства есть личность. */
    fun onServerPeers(peers: List<PeerInfo>, myPubKeyB64: String) {}

    /** Сервер отбраковал записи. Они уже удалены из очереди: отказ — почти наверняка ошибка протокола, повтор бессмыслен. */
    suspend fun onRejected(rejected: Map<String, String>) {}

    /**
     * Применить правку мастера у себя — «тихо», без новой записи обратно на сервер (правка уже в его истории, эхо было бы
     * дублем). Применение обязано быть идемпотентным: правка, подтверждение которой не дошло, придёт снова. Исключение
     * считается [MasterApply.Failed] с повтором.
     */
    suspend fun applyMasterChange(change: ChangeRecord): MasterApply = MasterApply.Applied
}

/**
 * Размер пачки и паузы. По умолчанию — как в ТЗ мастерского сервера (§3.4): бэкофф 1 → 2 → 5 → 15 → 60 с, простой — раз в 30 с.
 * [jitter] — случайный разброс каждой паузы (0.2 — ±20 %): сто телефонов, включённых разом, иначе опрашивали бы сервер строго
 * в одни и те же секунды, и после перезапуска сервера возвращались бы одной волной. Средняя пауза от разброса не меняется.
 */
class SyncConfig(
    val batchSize: Int = 200,
    val backoffMs: LongArray = longArrayOf(1_000, 2_000, 5_000, 15_000, 60_000),
    val idlePollMs: Long = 30_000,
    val noEndpointPollMs: Long = 30_000,
    val jitter: Double = 0.2,
    val random: Random = Random.Default,
) {
    /** [ms] с разбросом ±[jitter]. */
    fun spread(ms: Long): Long = if (jitter <= 0.0) ms else (ms * (1 + jitter * (2 * random.nextDouble() - 1))).toLong().coerceAtLeast(0)
}

/**
 * Фоновый обмен с мастерским сервером: отправляет очередь [ChangeRecord] пачками, удаляет принятые и отбракованные, применяет
 * правки мастера и подтверждает их следующим запросом. Сервер опрашивается ДАЖЕ когда очередь пуста — push-канала нет, и
 * только так телефон узнаёт о новой правке мастера. Недоступен сервер — бэкофф; сбой одной итерации (база, разбор ответа,
 * применение правки) не останавливает цикл. [wake] — не ждать паузу (новая запись в очереди, поменялся адрес сервера).
 *
 * [lastSummary] — итог последней попытки одной строкой (для снимка состояния в журнале).
 */
class SyncEngine(
    private val queue: ChangeQueue,
    private val transport: CollectorTransport,
    private val endpoint: () -> CollectorEndpoint?,
    private val subjectKey: () -> String?,
    private val presence: suspend (QueueStats) -> Map<String, Any?>? = { null },
    private val hooks: SyncHooks = object : SyncHooks {},
    private val clock: Clock = Clock.System,
    private val log: KitLog = NoopLog,
    private val tag: String = "Sync",
    private val config: SyncConfig = SyncConfig(),
) {
    private val wakeSignal = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    @Volatile var lastSummary: String = "ещё не было"
        private set

    fun wake() {
        wakeSignal.tryEmit(Unit)
    }

    /** Крутится, пока скоуп не отменят. Запускать один раз на процесс. */
    suspend fun run(): Nothing {
        // Ответы на правки мастера, о которых сервер ещё не знает: подтверждения применённых (только после них сервер перестаёт
        // присылать правку заново) и отказы по неприменённым. Уходят в следующем запросе.
        var replies = Replies.NONE
        var backoff = 0
        while (true) {
            try {
                val step = syncOnce(replies, backoff)
                replies = step.replies
                backoff = step.backoff
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                log.w(tag, "итерация синка упала: ${e.message}", e)
                lastSummary = "упал ${e.javaClass.simpleName} в ${hhmmss()}"
                val delayMs = backoffDelay(backoff)
                backoff++
                waitForWakeOrTimeout(delayMs)
            }
        }
    }

    private class Replies(val acks: List<String>, val failures: List<ApplyFailure>, val appliedAtSeq: Map<String, Long> = emptyMap()) {
        companion object { val NONE = Replies(emptyList(), emptyList()) }
    }

    private class Step(val replies: Replies, val backoff: Int)

    private suspend fun syncOnce(repliesIn: Replies, backoffIn: Int): Step {
        val target = endpoint()
        if (target == null) {
            waitForWakeOrTimeout(config.spread(config.noEndpointPollMs))
            return Step(repliesIn, 0)
        }

        val batch = queue.nextBatch(config.batchSize)
        val subject = subjectKey()
        val pendingCount = queue.count()
        val oldestAgeMs = queue.oldestHappenedAt()?.let { (clock.nowMs() - it).coerceAtLeast(0) } ?: 0L
        val heartbeat = if (subject != null) presence(QueueStats(pendingCount, oldestAgeMs)) else null
        val result = transport.exchange(target, SyncRequest(batch, subject, repliesIn.acks, heartbeat, repliesIn.failures, repliesIn.appliedAtSeq))

        if (result == null) {
            lastSummary = "нет связи в ${hhmmss()} (очередь $pendingCount, повтор ${backoffIn + 1})"
            waitForWakeOrTimeout(backoffDelay(backoffIn))
            return Step(repliesIn, backoffIn + 1)
        }

        lastSummary = "ok в ${hhmmss()} (отправлено ${batch.size}, принято ${result.accepted.size}, отбраковано ${result.rejected.size})"
        if (subject != null) hooks.onServerPeers(result.peers, subject)

        if (result.accepted.isNotEmpty()) queue.markAccepted(result.accepted.toList())
        if (result.rejected.isNotEmpty()) queue.deleteByIds(result.rejected.keys.toList())
        // Сервер знает меньше, чем уже подтвердил, — его восстановили из резервной копии: подтверждённые записи сверх его
        // последнего seq возвращаются в очередь и уходят снова (для сервера это новые записи, повтор с тем же id — не дубль).
        val lost = subject?.let { s -> result.knownSeq[s]?.let { known -> queue.requeueAcceptedAbove(s, known) } } ?: 0
        if (lost > 0) log.warnEvent(tag, "sync.server_lost_records", "count" to lost, "serverSeq" to result.knownSeq[subject])
        if (result.rejected.isNotEmpty()) {
            log.warnEvent(tag, "sync.rejected", "count" to result.rejected.size, "reasons" to result.rejected.values.take(5).joinToString(" | "), "ids" to result.rejected.keys.take(5).joinToString(","))
            hooks.onRejected(result.rejected)
        }
        // Запрос с repliesIn дошёл — сервер их учёл; новые ответы — по правкам, применённым (или нет) прямо сейчас.
        val replies = if (result.pending.isNotEmpty()) applyMasterChanges(result.pending) else Replies.NONE

        if (batch.isEmpty() && replies.acks.isEmpty() && lost == 0) {
            // Нечего слать и ничего не применили — обычный простой, не долбим сервер чаще раза в idlePollMs. Сюда же — правки,
            // которые не применились: сервер пришлёт их снова, но повторять раньше следующего опроса бессмысленно.
            waitForWakeOrTimeout(config.spread(config.idlePollMs))
        }
        // Иначе сразу на новый виток: либо не всё отправили (пачка), либо только что применили правки и надо отправить
        // подтверждения и проверить очередь ещё раз без задержки.
        return Step(replies, 0)
    }

    /** Подтверждаются только применённые правки; остальные — отказом с причиной (сервер решает, слать ли снова). */
    private suspend fun applyMasterChanges(pending: List<ChangeRecord>): Replies {
        val acks = mutableListOf<String>()
        val failures = mutableListOf<ApplyFailure>()
        val appliedAtSeq = mutableMapOf<String, Long>()
        for (change in pending) {
            val outcome = try {
                hooks.applyMasterChange(change)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                log.w(tag, "не удалось применить правку ${change.id}: ${e.message}", e)
                MasterApply.Failed("${e.javaClass.simpleName}: ${e.message}", permanent = false)
            }
            when (outcome) {
                MasterApply.Applied -> {
                    acks += change.id
                    // Всё, что телефон записал до этого момента (seq ≤ lastSeq), случилось до правки, остальное — после.
                    appliedAtSeq[change.id] = queue.lastSeq()
                }
                is MasterApply.Failed -> {
                    log.warnEvent(tag, "master.apply_failed", "id" to change.id, "field" to change.field, "reason" to outcome.reason, "permanent" to outcome.permanent)
                    failures += ApplyFailure(change.id, outcome.reason, outcome.permanent)
                }
            }
        }
        return Replies(acks, failures, appliedAtSeq)
    }

    private fun backoffDelay(index: Int): Long = config.spread(config.backoffMs[index.coerceIn(0, config.backoffMs.lastIndex)])

    private suspend fun waitForWakeOrTimeout(timeoutMs: Long) {
        withTimeoutOrNull(timeoutMs) { wakeSignal.first() }
    }

    private fun hhmmss(): String = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(clock.nowMs()))
}
