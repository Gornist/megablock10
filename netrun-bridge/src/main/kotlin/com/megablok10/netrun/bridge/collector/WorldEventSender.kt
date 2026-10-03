package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.sync.CollectorEndpoint
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

/** Настройки отправки быстрых событий; значения по умолчанию — боевые, тесты ставят короткие паузы и малую очередь. */
data class WorldEventConfig(
    /** Сколько событий держит очередь в памяти; при переполнении старое выбрасывается (свежее важнее). */
    val queueCapacity: Int = 100,
    /** Пауза перед единственной повторной попыткой. Событие живёт ≈ 5 с: длинная пауза съела бы его. */
    val retryDelayMs: Long = 400,
    val connectTimeoutMs: Long = 2_000,
    val requestTimeoutMs: Long = 3_000,
    /** Как долго помнится, что коллектор принимает быстрые события (`capabilities.world_events`). */
    val capabilityTtlMs: Long = 5 * 60_000,
    /** Как долго помнится «не принимает»: события за это время выбрасываются без запроса, чтобы не стучать в `/api/capabilities` на каждое. */
    val notCapableTtlMs: Long = 15_000,
    /** Не чаще одного предупреждения данного вида за этот срок: затяжной обрыв не заливает журнал строкой на событие. */
    val warnEveryMs: Long = 30_000,
)

/**
 * Отправка быстрых событий на точки площадки (docs/netrun-world-records.md, разделы 3 и 8): `POST /api/world-events` на коллектор.
 *
 * Не `SyncEngine`: события живут `ttl_ms` ≈ 5 с, поэтому очереди на диск и догонки нет. Событие выжило, если коллектор принял его
 * сразу или со второй попытки; иначе оно забыто (сирена, прозвучавшая через минуту, хуже тишины). Решающее остаётся в записях мира.
 *
 * - [offer] не блокирует: зовётся из слушателя хранилища под его замком, поэтому только кладёт события в очередь в памяти
 *   (ограничена [WorldEventConfig.queueCapacity], при переполнении старое выбрасывается) и будит [run]. Сеть — вне замка, в [run].
 * - Перед отправкой — открытый `GET /api/capabilities`: шлём, только когда `world_events` равен [SUPPORTED_WORLD_EVENTS].
 * - Просроченное ([FastEvent.ts] + [FastEvent.ttlMs] по [clock]) не отправляется — ни с первой попытки, ни с повторной.
 * - Коллектор недоступен — Мост работает дальше: предупреждение в журнал (без секрета, реже раза в [WorldEventConfig.warnEveryMs]).
 */
internal class WorldEventSender(
    private val endpoint: CollectorEndpoint,
    private val clock: () -> Long = System::currentTimeMillis,
    private val config: WorldEventConfig = WorldEventConfig(),
    private val log: KitLog = NoopLog,
    httpClient: HttpClient? = null,
    /** Монотонные мс для сроков памяти о возможностях и частоты предупреждений: не зависят от [clock], который в тестах стоит на месте. */
    private val monotonic: () -> Long = { System.nanoTime() / NANOS_IN_MS },
) {
    private val http: HttpClient = httpClient ?: HttpClient.newBuilder().connectTimeout(Duration.ofMillis(config.connectTimeoutMs)).build()
    private val lock = Any()
    private val pending = ArrayDeque<FastEvent>()
    private val wake = Channel<Unit>(Channel.CONFLATED)

    @Volatile private var capableUntil = Long.MIN_VALUE
    @Volatile private var notCapableUntil = Long.MIN_VALUE
    private val warnLock = Any()
    private val lastWarnAt = HashMap<String, Long>()
    private val suppressed = HashMap<String, Int>()

    init {
        require(config.queueCapacity >= 1) { "queueCapacity должен быть положительным" }
    }

    /** Сколько событий ждёт отправки (для тестов и диагностики); после отправки или отказа — 0, ничего не копится. */
    val queued: Int get() = synchronized(lock) { pending.size }

    /** Положить события в очередь и разбудить отправку. Не блокирует и не бросает. */
    fun offer(events: List<FastEvent>) {
        if (events.isEmpty()) return
        var dropped = 0
        synchronized(lock) {
            for (e in events) {
                if (pending.size >= config.queueCapacity) {
                    pending.removeFirst()
                    dropped++
                }
                pending.addLast(e)
            }
        }
        if (dropped > 0) warnThrottled("world_events.overflow", "dropped" to dropped, "capacity" to config.queueCapacity)
        wake.trySend(Unit)
    }

    fun start(scope: CoroutineScope): Job = scope.launch { run() }

    /** Цикл отправки: разбирает очередь пачками (≤ [MAX_BATCH], предел приёма), пока не отменят. */
    suspend fun run() {
        while (true) {
            val batch = take()
            if (batch.isEmpty()) {
                wake.receive()
                continue
            }
            try {
                withContext(Dispatchers.IO) { deliver(batch) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Сбой отправки событий не должен останавливать ни цикл, ни Мост: событие забыто.
                warnThrottled("world_events.failed", "error" to e.javaClass.simpleName, "events" to batch.size)
            }
        }
    }

    private fun take(): List<FastEvent> = synchronized(lock) {
        val n = minOf(MAX_BATCH, pending.size)
        List(n) { pending.removeFirst() }
    }

    /** Одна попытка и одна повторная; не вышло — забыть. */
    private suspend fun deliver(batch: List<FastEvent>) {
        var live = fresh(batch)
        if (live.isEmpty()) return
        var failure = attempt(live) ?: return
        if (failure.retry) {
            delay(config.retryDelayMs)
            live = fresh(live) // за паузу часть событий могла дожить до срока
            if (live.isEmpty()) return
            failure = attempt(live) ?: return
        }
        warnThrottled(failure.name, *failure.fields, "dropped" to live.size)
    }

    /** События, которые ещё живы по [FastEvent.ttlMs]; просроченные отбрасываются (условие приёма: `now > ts + ttl_ms`). */
    private fun fresh(events: List<FastEvent>): List<FastEvent> {
        val now = clock()
        val (live, expired) = events.partition { now <= it.ts + it.ttlMs }
        if (expired.isNotEmpty()) warnThrottled("world_events.expired", "dropped" to expired.size)
        return live
    }

    private class Failure(val name: String, val retry: Boolean, val fields: Array<Pair<String, Any?>>)

    /** null — коллектор принял событие. Иначе чем кончилось и стоит ли повторять. */
    private fun attempt(live: List<FastEvent>): Failure? {
        val base = endpoint.baseUrl.trimEnd('/')
        val secret = endpoint.secret
        // Секрет, непригодный для заголовка, JDK принял бы исключением с самим секретом в тексте: в журнал не пишем ни его, ни текст.
        if (!secret.isNullOrBlank() && !WorldCollectorTransport.isValidSecret(secret)) return Failure("world_events.bad_secret", false, arrayOf("url" to base))
        return when (capable(base)) {
            Capable.YES -> post(base, secret, live)
            Capable.NO -> Failure("world_events.not_supported", false, arrayOf("url" to base, "need" to SUPPORTED_WORLD_EVENTS))
            Capable.UNREACHABLE -> Failure("world_events.unreachable", true, arrayOf("url" to base))
        }
    }

    private enum class Capable { YES, NO, UNREACHABLE }

    /** `GET /api/capabilities`: открытый, без секрета. Помнит ответ: «да» — [WorldEventConfig.capabilityTtlMs], «нет» — [WorldEventConfig.notCapableTtlMs]. */
    private fun capable(base: String): Capable {
        val t = monotonic()
        if (t < capableUntil) return Capable.YES
        if (t < notCapableUntil) return Capable.NO
        val version = try {
            fetchWorldEventsVersion(base)
        } catch (e: IOException) {
            return Capable.UNREACHABLE
        }
        return if (version == SUPPORTED_WORLD_EVENTS) {
            capableUntil = t + config.capabilityTtlMs
            Capable.YES
        } else {
            notCapableUntil = t + config.notCapableTtlMs
            Capable.NO
        }
    }

    /** Версия `world_events` из ответа; null — коллектор ответил, но возможности не объявил (404 у старого, не JSON). Сбой связи и 5xx — [IOException]. */
    private fun fetchWorldEventsVersion(base: String): Int? {
        val resp = http.send(
            HttpRequest.newBuilder(URI.create("$base/api/capabilities")).timeout(Duration.ofMillis(config.requestTimeoutMs)).GET().build(),
            HttpResponse.BodyHandlers.ofString(Charsets.UTF_8),
        )
        return when (resp.statusCode()) {
            in HTTP_SERVER_ERROR -> throw IOException("capabilities: HTTP ${resp.statusCode()}")
            in HTTP_OK -> runCatching { Json.parseToJsonElement(resp.body()).jsonObject["world_events"]?.jsonPrimitive?.intOrNull }.getOrNull()
            else -> null
        }
    }

    private fun post(base: String, secret: String?, live: List<FastEvent>): Failure? {
        val request = try {
            HttpRequest.newBuilder(URI.create("$base/api/world-events"))
                .timeout(Duration.ofMillis(config.requestTimeoutMs))
                .header("Content-Type", "application/json; charset=utf-8")
                .apply { if (!secret.isNullOrBlank()) header("X-Game-Secret", secret) }
                .POST(HttpRequest.BodyPublishers.ofString(encode(live).toString(), Charsets.UTF_8))
                .build()
        } catch (e: IllegalArgumentException) {
            return Failure("world_events.bad_request", false, arrayOf("url" to base, "error" to e.javaClass.simpleName)) // текст может повторять заголовки
        }
        val response = try {
            http.send(request, HttpResponse.BodyHandlers.ofString(Charsets.UTF_8))
        } catch (e: IOException) {
            return Failure("world_events.unreachable", true, arrayOf("url" to base, "error" to e.javaClass.simpleName))
        }
        val code = response.statusCode()
        return when {
            code in HTTP_OK -> null.also { report(base, live.size, response.body()) }
            // 5xx — сбой на стороне коллектора, повтор осмыслен; 4xx (секрет, лимит частоты, форма) за 0.4 с не пройдёт.
            code in HTTP_SERVER_ERROR -> Failure("world_events.http_error", true, arrayOf("url" to base, "code" to code))
            else -> Failure("world_events.http_error", false, arrayOf("url" to base, "code" to code))
        }
    }

    /** Итог приёма: `{accepted, expired, duplicate, invalid}`. Просроченные и невалидные у коллектора — знак рассинхрона часов или формата. */
    private fun report(base: String, sent: Int, body: String) {
        val o = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull()
        fun n(k: String) = o?.get(k)?.jsonPrimitive?.intOrNull
        log.event(TAG, "world_events.sent", "sent" to sent, "accepted" to n("accepted"), "duplicate" to n("duplicate"))
        val expired = n("expired") ?: 0
        val invalid = n("invalid") ?: 0
        if (expired > 0 || invalid > 0) warnThrottled("world_events.rejected", "url" to base, "expired" to expired, "invalid" to invalid)
    }

    private fun warnThrottled(name: String, vararg fields: Pair<String, Any?>) {
        val skipped: Int
        synchronized(warnLock) {
            val t = monotonic()
            val last = lastWarnAt[name]
            if (last != null && t - last < config.warnEveryMs) {
                suppressed[name] = (suppressed[name] ?: 0) + 1
                return
            }
            lastWarnAt[name] = t
            skipped = suppressed.remove(name) ?: 0
        }
        log.warnEvent(TAG, name, *fields, "suppressed" to skipped.takeIf { it > 0 })
    }

    companion object {
        const val TAG = "WorldEvents"

        /** Версия приёма быстрых событий, которую Мост умеет слать и коллектор объявляет в `capabilities.world_events`. */
        const val SUPPORTED_WORLD_EVENTS = 1

        /** Событий в одном запросе: больше коллектор не принимает (`MAX_EVENTS`). */
        const val MAX_BATCH = 50
        private const val NANOS_IN_MS = 1_000_000L
        private val HTTP_OK = 200..299
        private val HTTP_SERVER_ERROR = 500..599

        /** Тело запроса: `{"events":[…]}`, поля события — раздел 3 контракта (`ttl_ms` с подчёркиванием, пустые — `null`). */
        internal fun encode(events: List<FastEvent>): JsonObject = JsonObject(
            mapOf(
                "events" to JsonArray(
                    events.map {
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(it.id), "kind" to JsonPrimitive(it.kind), "ts" to JsonPrimitive(it.ts), "ttl_ms" to JsonPrimitive(it.ttlMs),
                                "node" to JsonPrimitive(it.node), "terminal" to JsonPrimitive(it.terminal), "session" to JsonPrimitive(it.session),
                                "level" to JsonPrimitive(it.level),
                            ),
                        )
                    },
                ),
            ),
        )
    }
}
