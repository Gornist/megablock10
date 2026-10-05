package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.CollectorTransport
import com.megablok10.kit.sync.SyncRequest
import com.megablok10.kit.sync.SyncResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.IOException
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

/**
 * HTTP-транспорт Моста до коллектора для kit `SyncEngine`: тот же `POST /api/changes`, что у телефонов, на `java.net.http` (JDK 17).
 *
 * **Запись мира нельзя слать вслепую.** После ответа `rejected` kit удаляет запись из очереди, а коллектор, не знающий `net.*`,
 * отвечает именно так: запись пропала бы молча (C2, раздел 1). Поэтому перед любой отправкой транспорт спрашивает открытый
 * `GET /api/capabilities` и шлёт, только когда `world_records` равен [SUPPORTED_WORLD_RECORDS]; иначе возвращает null («нет связи»),
 * очередь остаётся целой, а `SyncEngine` повторяет по своему бэкоффу. Положительный ответ помнится [capabilityTtlMs].
 */
class WorldCollectorTransport(
    private val http: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(CONNECT_TIMEOUT_S)).build(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val log: KitLog = NoopLog,
    private val capabilityTtlMs: Long = CAPABILITY_TTL_MS,
) : CollectorTransport {
    @Volatile private var capableUntil = 0L

    /** Что коллектор отвечал про `world_records` в последний раз (для журнала: пишем первый ответ и смену). */
    @Volatile private var lastReported: Int? = null
    @Volatile private var reportedOnce = false

    override suspend fun exchange(endpoint: CollectorEndpoint, request: SyncRequest): SyncResponse? = withContext(Dispatchers.IO) {
        val base = endpoint.baseUrl.trimEnd('/')
        if (!collectorKnowsWorldRecords(base)) return@withContext null
        try {
            post(base, endpoint.secret, request)
        } catch (e: IOException) {
            log.warnEvent(TAG, "sync.unreachable", "url" to base, "error" to e.javaClass.simpleName, "msg" to e.message, "records" to request.records.size)
            null
        } catch (e: IllegalArgumentException) {
            // 200 с не-JSON телом или JSON не той формы (прокси, не тот сервер по адресу): цикл синка не останавливаем.
            log.warnEvent(TAG, "sync.bad_response", "url" to base, "msg" to e.message)
            null
        } catch (e: NoSuchElementException) {
            log.warnEvent(TAG, "sync.bad_response", "url" to base, "msg" to e.message)
            null
        }
    }

    private fun post(base: String, secret: String?, request: SyncRequest): SyncResponse? {
        // Секрет, непригодный для HTTP-заголовка (перевод строки, не-ASCII), JDK принял бы исключением с самим секретом в тексте.
        // Старт Моста такой секрет отвергает (Main.kt); сюда он доходит только в обход старта, и в журнал не попадает ни значение, ни текст исключения.
        if (!secret.isNullOrBlank() && !isValidSecret(secret)) {
            log.warnEvent(TAG, "sync.bad_secret", "url" to base, "records" to request.records.size)
            return null
        }
        val httpRequest = try {
            HttpRequest.newBuilder(URI.create("$base/api/changes"))
                .timeout(Duration.ofSeconds(REQUEST_TIMEOUT_S))
                .header("Content-Type", "application/json; charset=utf-8")
                .apply { if (!secret.isNullOrBlank()) header("X-Game-Secret", secret) }
                .POST(HttpRequest.BodyPublishers.ofString(encode(request).toString(), Charsets.UTF_8))
                .build()
        } catch (e: IllegalArgumentException) {
            // Текст исключения построения запроса не пишем: он может повторять заголовки (секрет игры).
            log.warnEvent(TAG, "sync.bad_request", "url" to base, "error" to e.javaClass.simpleName)
            return null
        }
        val response = http.send(httpRequest, HttpResponse.BodyHandlers.ofString(Charsets.UTF_8))
        if (response.statusCode() !in HTTP_OK) {
            log.warnEvent(TAG, "sync.http_error", "url" to base, "code" to response.statusCode(), "records" to request.records.size)
            return null
        }
        return decode(response.body()).also {
            log.event(TAG, "sync.ok", "sent" to request.records.size, "accepted" to it.accepted.size, "rejected" to it.rejected.size)
        }
    }

    /** `GET /api/capabilities`: открытый, без секрета. Недоступен, не JSON или `world_records` не тот — коллектор «не готов». */
    private fun collectorKnowsWorldRecords(base: String): Boolean {
        if (clock() < capableUntil) return true
        val reported = try {
            fetchWorldRecordsVersion(base)
        } catch (e: IOException) {
            log.warnEvent(TAG, "world.capabilities_unreachable", "url" to base, "error" to e.javaClass.simpleName)
            return false
        } catch (e: IllegalArgumentException) {
            null // не JSON или не объект: тот же ответ, что «возможности не объявлены»
        }
        if (!reportedOnce || reported != lastReported) {
            val fields = arrayOf("url" to base, "world_records" to reported, "need" to SUPPORTED_WORLD_RECORDS)
            if (reported == SUPPORTED_WORLD_RECORDS) log.event(TAG, "world.capabilities", *fields) else log.warnEvent(TAG, "world.capabilities", *fields)
        }
        reportedOnce = true
        lastReported = reported
        if (reported != SUPPORTED_WORLD_RECORDS) return false
        capableUntil = clock() + capabilityTtlMs
        return true
    }

    private fun fetchWorldRecordsVersion(base: String): Int? {
        val req = HttpRequest.newBuilder(URI.create("$base/api/capabilities")).timeout(Duration.ofSeconds(REQUEST_TIMEOUT_S)).GET().build()
        val resp = http.send(req, HttpResponse.BodyHandlers.ofString(Charsets.UTF_8))
        if (resp.statusCode() !in HTTP_OK) return null
        return Json.parseToJsonElement(resp.body()).jsonObject["world_records"]?.jsonPrimitive?.intOrNull
    }

    companion object {
        const val TAG = "WorldSync"

        /**
         * Версия формата записей мира, которую Мост пишет и коллектор объявляет в `capabilities.world_records`: 1 — записи v1,
         * 2 — плюс `net.breach`/`NET_BREACH`. Коллектор с 1 не знает новой причины и отверг бы её; пока он не объявил 2, очередь стоит целой.
         */
        const val SUPPORTED_WORLD_RECORDS = 2
        private const val CONNECT_TIMEOUT_S = 5L
        private const val REQUEST_TIMEOUT_S = 10L
        private const val CAPABILITY_TTL_MS = 5 * 60 * 1000L
        private val HTTP_OK = 200..299

        /** Секрет игры годится для заголовка `X-Game-Secret`, если состоит только из печатных ASCII-символов (код 0x20–0x7E). */
        fun isValidSecret(secret: String): Boolean = secret.all { it in ' '..'~' }

        internal fun encode(r: SyncRequest): JsonObject {
            val body = LinkedHashMap<String, JsonElement>()
            body["records"] = JsonArray(r.records.map { it.toJson() })
            r.subjectKeyB64?.let { body["subjectKeyB64"] = JsonPrimitive(it) }
            if (r.ackIds.isNotEmpty()) body["ackIds"] = JsonArray(r.ackIds.map { JsonPrimitive(it) })
            if (r.appliedAtSeq.isNotEmpty()) body["appliedAtSeq"] = JsonObject(r.appliedAtSeq.mapValues { JsonPrimitive(it.value) })
            if (r.failures.isNotEmpty()) {
                body["failures"] = JsonArray(r.failures.map { JsonObject(mapOf("id" to JsonPrimitive(it.id), "error" to JsonPrimitive(it.reason), "permanent" to JsonPrimitive(it.permanent))) })
            }
            r.presence?.let { body["presence"] = JsonObject(it.mapValues { (_, v) -> scalar(v) }) }
            return JsonObject(body)
        }

        private fun scalar(v: Any?): JsonElement = when (v) {
            null -> JsonNull
            is Boolean -> JsonPrimitive(v)
            is Number -> JsonPrimitive(v)
            else -> JsonPrimitive(v.toString())
        }

        private fun ChangeRecord.toJson() = JsonObject(
            mapOf(
                "id" to JsonPrimitive(id), "subjectKeyB64" to JsonPrimitive(subjectKeyB64), "seq" to JsonPrimitive(seq),
                "happenedAt" to JsonPrimitive(happenedAt), "field" to JsonPrimitive(field), "oldValue" to JsonPrimitive(oldValue),
                "newValue" to JsonPrimitive(newValue), "reason" to JsonPrimitive(reason), "sourceRef" to JsonPrimitive(sourceRef),
                "actor" to JsonPrimitive(actor), "signature" to JsonPrimitive(signature),
            ),
        )

        internal fun decode(text: String): SyncResponse {
            val json = Json.parseToJsonElement(text).jsonObject
            val accepted = json.getValue("accepted").jsonArray.map { it.jsonPrimitive.content }.toSet()
            val rejected = json.getValue("rejected").jsonArray.associate { item ->
                val o = item.jsonObject
                o.getValue("id").jsonPrimitive.content to (o["error"]?.jsonPrimitive?.contentOrNull ?: "")
            }
            val pending = json["pending"]?.jsonArray.orEmpty().map { it.jsonObject.toRecord() }
            val knownSeq = json["knownSeq"]?.jsonObject.orEmpty().mapValues { it.value.jsonPrimitive.longOrNull ?: 0L }
            return SyncResponse(accepted, rejected, pending, emptyList<PeerInfo>(), knownSeq)
        }

        private fun JsonObject.toRecord() = ChangeRecord(
            id = getValue("id").jsonPrimitive.content, subjectKeyB64 = getValue("subjectKeyB64").jsonPrimitive.content,
            seq = getValue("seq").jsonPrimitive.content.toLong(), happenedAt = getValue("happenedAt").jsonPrimitive.content.toLong(),
            field = getValue("field").jsonPrimitive.content, oldValue = this["oldValue"]?.jsonPrimitive?.contentOrNull,
            newValue = this["newValue"]?.jsonPrimitive?.contentOrNull, reason = getValue("reason").jsonPrimitive.content,
            sourceRef = this["sourceRef"]?.jsonPrimitive?.contentOrNull, actor = getValue("actor").jsonPrimitive.content,
            signature = this["signature"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        )
    }
}
