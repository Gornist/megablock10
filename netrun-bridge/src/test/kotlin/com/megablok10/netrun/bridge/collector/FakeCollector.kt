package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.crypto.Ecdsa
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * Фейковый коллектор: настоящий HTTP-сервер на 127.0.0.1, который принимает `POST /api/changes` по тем же правилам, что
 * `admin-web/server/src/lib/changeIngest.ts` (закрытые списки полей и причин, автор = субъект, подпись ECDSA по pipe-строке,
 * повтор того же `id` — «принято» без второй записи, другая запись с занятым `id` или `seq` — отказ, `newValue` — JSON-объект
 * ≤ 4096), `POST /api/world-events` по правилам `routes/worldEvents.ts` + `lib/worldEvents.ts` (виды из семи, `id`, `ts`, `ttl_ms`, секрет игры,
 * просроченное и повторное отбрасывается, ответ `{accepted, expired, duplicate, invalid}`) и открытый `GET /api/capabilities`. Подпись проверяется своим кодом теста, а не кодом Моста: если Мост и коллектор
 * разойдутся в байтах, тест красный.
 */
class FakeCollector : AutoCloseable {
    private val server: HttpServer = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0)

    /** Что коллектор хранит: `id` → запись. */
    val stored: MutableMap<String, JsonObject> = java.util.Collections.synchronizedMap(LinkedHashMap<String, JsonObject>())

    /** Ответ `GET /api/capabilities`: тело JSON или null — 404 (старый коллектор без этой ручки). */
    @Volatile var capabilities: String? = """{"world_records":1,"world_events":1}"""

    /** Следующий ответ на `POST /api/changes` запись принимает, но до клиента не доходит (обрыв сети после приёма). */
    @Volatile var dropNextResponse = false

    /** Причины, которых этот «старый» коллектор не знает: записи с ними отклоняются как `unknown reason`. */
    @Volatile var unknownReasons: Set<String> = emptySet()

    /** Секрет игры: пусто — не проверяется. */
    @Volatile var requiredSecret: String? = null

    /** Следующие N ответов на `POST /api/world-events` — 503 (событие не принято). */
    val failEventPosts = AtomicInteger()

    /** Следующий ответ на `POST /api/world-events` событие принимает, но до клиента не доходит. */
    @Volatile var dropNextEventResponse = false

    /** Следующие N ответов на `POST /api/world-events` не доходят до клиента (обрыв посреди запроса, и на повторе тоже). */
    val dropEventResponses = AtomicInteger()

    /** Сколько обработчик событий «думает» перед ответом (коллектор завис). */
    @Volatile var eventDelayMs = 0L

    /** «Сейчас» коллектора для срока жизни событий: тесты с часами стенда (время документов ~1000 мс) ставят свои. */
    @Volatile var eventClock: () -> Long = System::currentTimeMillis

    val changePosts = AtomicInteger()
    val capabilityGets = AtomicInteger()
    val recordIdsSent = CopyOnWriteArrayList<String>()
    val secretsSeen = CopyOnWriteArrayList<String?>()
    val bodies = CopyOnWriteArrayList<JsonObject>()

    /** Быстрые события: запросы, секреты в заголовках, принятые события (по порядку приёма) и все `id` как пришли, с повторами. */
    val eventPosts = AtomicInteger()
    val eventSecrets = CopyOnWriteArrayList<String?>()
    val events = CopyOnWriteArrayList<JsonObject>()
    val eventIdsSent = CopyOnWriteArrayList<String>()
    val eventsInvalid = AtomicInteger()
    val eventsExpired = AtomicInteger()
    val eventsDuplicate = AtomicInteger()
    private val seenEventIds = java.util.Collections.synchronizedSet(HashSet<String>())

    val url: String get() = "http://127.0.0.1:${server.address.port}"

    init {
        server.createContext("/api/capabilities") { ex ->
            capabilityGets.incrementAndGet()
            val body = capabilities
            if (body == null) reply(ex, 404, """{"error":"not found"}""") else reply(ex, 200, body)
        }
        server.createContext("/api/changes") { ex -> handleChanges(ex) }
        server.createContext("/api/world-events") { ex -> handleEvents(ex) }
        // Зависший обработчик событий не должен держать остальные запросы (по умолчанию HttpServer обслуживает по одному).
        server.executor = java.util.concurrent.Executors.newCachedThreadPool { r -> Thread(r, "fake-collector").apply { isDaemon = true } }
        server.start()
    }

    /** Виды принятых событий по порядку приёма. */
    fun eventKinds(): List<String> = events.map { it.str("kind")!! }

    private fun handleEvents(ex: HttpExchange) {
        eventPosts.incrementAndGet()
        eventSecrets += ex.requestHeaders.getFirst("X-Game-Secret")
        val raw = String(ex.requestBody.readBytes(), Charsets.UTF_8)
        if (eventDelayMs > 0) Thread.sleep(eventDelayMs)
        if (failEventPosts.getAndUpdate { if (it > 0) it - 1 else 0 } > 0) return reply(ex, 503, """{"error":"unavailable"}""")
        val secret = requiredSecret
        if (!secret.isNullOrEmpty() && ex.requestHeaders.getFirst("X-Game-Secret") != secret) return reply(ex, 401, """{"error":"invalid or missing X-Game-Secret"}""")
        val list = (runCatching { Json.parseToJsonElement(raw).jsonObject["events"] }.getOrNull() as? JsonArray) ?: return reply(ex, 400, """{"error":"events must be an array"}""")
        if (list.size > MAX_EVENTS) return reply(ex, 400, """{"error":"too many events"}""")
        var accepted = 0
        var expired = 0
        var duplicate = 0
        var invalid = 0
        for (e in list) {
            val o = e as? JsonObject
            o?.str("id")?.let { eventIdsSent += it }
            when {
                o == null || !validEvent(o) -> invalid++
                eventClock() > o.long("ts") + (o["ttl_ms"]?.let { o.long("ttl_ms") } ?: DEFAULT_TTL_MS) -> expired++
                !seenEventIds.add(o.str("id")!!) -> duplicate++
                else -> { events += o; accepted++ }
            }
        }
        eventsInvalid.addAndGet(invalid)
        eventsExpired.addAndGet(expired)
        eventsDuplicate.addAndGet(duplicate)
        if (dropNextEventResponse || dropEventResponses.getAndUpdate { if (it > 0) it - 1 else 0 } > 0) {
            dropNextEventResponse = false
            ex.close()
            return
        }
        reply(ex, 200, """{"accepted":$accepted,"expired":$expired,"duplicate":$duplicate,"invalid":$invalid}""")
    }

    /** `parseWorldEvent` коллектора: один из семи видов, `id` ≤ 100, целые `ts` > 0 и `ttl_ms` 0..60000, ссылки — строки ≤ 100 или `null`. */
    private fun validEvent(o: JsonObject): Boolean {
        val id = o.str("id")
        if (id.isNullOrEmpty() || id.length > MAX_REF || o.str("kind") !in EVENT_KINDS) return false
        val ts = (o["ts"] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
        if (ts == null || ts <= 0) return false
        val ttl = o["ttl_ms"]?.let { (it as? JsonPrimitive)?.takeIf { p -> !p.isString }?.longOrNull ?: return false } ?: DEFAULT_TTL_MS
        if (ttl !in 0..MAX_TTL_MS) return false
        return listOf("node", "terminal", "session", "level").all { k ->
            val v = o[k]
            v == null || v is JsonNull || (v is JsonPrimitive && v.isString && v.content.length <= MAX_REF)
        }
    }

    /** Коллектор потерял всё (восстановлен из пустой копии). */
    fun wipe() = stored.clear()

    private fun handleChanges(ex: HttpExchange) {
        changePosts.incrementAndGet()
        secretsSeen += ex.requestHeaders.getFirst("X-Game-Secret")
        val secret = requiredSecret
        if (!secret.isNullOrEmpty() && ex.requestHeaders.getFirst("X-Game-Secret") != secret) {
            reply(ex, 401, """{"error":"invalid or missing X-Game-Secret"}""")
            return
        }
        val body = Json.parseToJsonElement(String(ex.requestBody.readBytes(), Charsets.UTF_8)).jsonObject
        bodies += body
        val records = body["records"]?.jsonArray.orEmpty()
        val subject = body["subjectKeyB64"]?.jsonPrimitive?.contentOrNull
        val accepted = ArrayList<String>()
        val rejected = ArrayList<JsonElement>()
        synchronized(stored) {
            for (r in records) {
                val o = r.jsonObject
                val id = o.getValue("id").jsonPrimitive.content
                recordIdsSent += id
                val error = ingest(o)
                if (error == null) accepted += id else rejected += JsonObject(mapOf("id" to JsonPrimitive(id), "error" to JsonPrimitive(error)))
            }
        }
        if (dropNextResponse) {
            dropNextResponse = false
            ex.close()
            return
        }
        val known = subject?.let { s -> mapOf(s to JsonPrimitive(stored.values.filter { it.str("subjectKeyB64") == s }.maxOfOrNull { it.long("seq") } ?: 0L)) }.orEmpty()
        val resp = JsonObject(
            mapOf(
                "accepted" to JsonArray(accepted.map { JsonPrimitive(it) }), "rejected" to JsonArray(rejected), "knownSeq" to JsonObject(known),
                "pending" to JsonArray(emptyList()), "peers" to JsonArray(emptyList()),
            ),
        )
        reply(ex, 200, resp.toString())
    }

    /** null — принято; иначе причина отказа, как в `changeIngest.ts`. */
    private fun ingest(r: JsonObject): String? {
        val id = r.str("id")!!
        stored[id]?.let { return if (sameRecord(it, r)) null else "id already used by a different record" }
        val problem = validate(r)
        if (problem != null) return problem
        val subject = r.str("subjectKeyB64")
        if (stored.values.any { it.str("subjectKeyB64") == subject && it.long("seq") == r.long("seq") }) return "seq already used by a different record"
        stored[id] = r
        return null
    }

    private fun validate(r: JsonObject): String? {
        val field = r.str("field")!!
        val reason = r.str("reason")!!
        if (field !in FIELDS) return "unknown field: $field"
        if (reason !in REASONS || reason in unknownReasons) return "unknown reason: $reason"
        if (r.str("actor") != r.str("subjectKeyB64")) return "actor must equal subjectKeyB64 for this reason"
        if (field.startsWith("net.")) valueProblem(r.str("newValue"))?.let { return it }
        return if (Ecdsa.verify(r.str("actor")!!, signaturePayload(r).toByteArray(Charsets.UTF_8), r.str("signature").orEmpty())) null else "invalid signature"
    }

    private fun valueProblem(v: String?): String? {
        if (v == null || v.length > MAX_JSON_CHARS) return "net value must be a JSON object up to $MAX_JSON_CHARS chars"
        val parsed = runCatching { Json.parseToJsonElement(v) }.getOrNull()
        return if (parsed is JsonObject) null else "net value must be a JSON object"
    }

    private fun sameRecord(a: JsonObject, b: JsonObject) = KEYS.all { a[it] == b[it] }

    private fun reply(ex: HttpExchange, code: Int, body: String) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        ex.responseHeaders.add("Content-Type", "application/json; charset=utf-8")
        ex.sendResponseHeaders(code, bytes.size.toLong())
        ex.responseBody.use { it.write(bytes) }
    }

    override fun close() = server.stop(0)

    companion object {
        /** Закрытые списки `lib/changeRecord.ts` (только записи мира: остальные поля игроков тестам не нужны). */
        private val FIELDS = setOf("balance", "net.run", "net.item", "net.alert")
        private val REASONS = setOf("TRANSFER_IN", "NET_ENTER", "NET_EXIT", "NET_FLATLINE", "NET_ITEM_OWNER", "NET_ALERT")
        private const val MAX_JSON_CHARS = 4096
        private const val MAX_EVENTS = 50
        private const val MAX_REF = 100
        private const val MAX_TTL_MS = 60_000L
        private const val DEFAULT_TTL_MS = 5_000L
        private val EVENT_KINDS = setOf("run.enter", "run.exit", "trace.level", "ice.hunt", "flatline", "lockdown", "alert.master")
        private val KEYS = listOf("subjectKeyB64", "seq", "happenedAt", "field", "oldValue", "newValue", "reason", "sourceRef", "actor", "signature")

        /** `signaturePayload` коллектора (`lib/changeRecord.ts`): pipe-строка из полей как пришли, null — пустое поле. */
        fun signaturePayload(r: JsonObject): String = listOf("id", "subjectKeyB64", "seq", "happenedAt", "field", "oldValue", "newValue", "reason", "sourceRef", "actor")
            .joinToString("|") { k -> r[k]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content.orEmpty() }

        fun JsonObject.str(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
        fun JsonObject.long(k: String): Long = (this[k] as? JsonPrimitive)?.longOrNull ?: 0L
    }
}
