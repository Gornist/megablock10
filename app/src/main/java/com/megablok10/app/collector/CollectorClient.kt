package com.megablok10.app.collector

import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.CollectorTransport
import com.megablok10.kit.sync.SyncRequest
import com.megablok10.kit.sync.SyncResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

private const val TAG = "CollectorClient"
private val JSON = "application/json; charset=utf-8".toMediaType()

/**
 * HTTP-клиент до мастерского коллектора (admin-web/server) — обычный POST
 * в открытой локальной сети, без TLS (см. network_security_config.xml).
 * Не P2P: в отличие от ChatServer и заявок на слоты это единственное место в
 * приложении, где устройство говорит с фиксированным сервером, а не с
 * другими игроками напрямую.
 *
 * Для синхронизации это транспорт kit ([CollectorTransport], движок — SyncEngine): здесь только HTTP и JSON.
 */
class CollectorClient(
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build(),
) : CollectorTransport {

    /**
     * POST /api/changes — см. §3.1 ТЗ. null означает "сеть/коллектор
     * недоступны", не "коллектор отбраковал всё". subjectKeyB64 передаётся
     * ВСЕГДА, даже при пустом records — этим же запросом сервер отдаёт
     * накопленные MASTER_OVERRIDE для этого ключа (§6.3), а без явного
     * ключа в пустом батче ему неоткуда узнать, чью очередь проверять.
     * peers в ответе — другие игроки, недавно приславшие heartbeat, с адресом и портом: запасное обнаружение, когда NSD молчит.
     */
    override suspend fun exchange(endpoint: CollectorEndpoint, request: SyncRequest): SyncResponse? = withContext(Dispatchers.IO) {
        val baseUrl = endpoint.baseUrl
        val records = request.records
        val body = JSONObject().put("records", JSONArray(records.map { it.toJson() }))
        if (request.subjectKeyB64 != null) body.put("subjectKeyB64", request.subjectKeyB64)
        // Подтверждение применённых правок мастера из прошлого ответа — сервер шлёт их снова, пока не получит ack.
        if (request.ackIds.isNotEmpty()) body.put("ackIds", JSONArray(request.ackIds))
        // Правки, которые применить не удалось: сервер считает попытки и после нескольких (или сразу, если повтор бесполезен) показывает их мастеру.
        if (request.failures.isNotEmpty()) {
            body.put("failures", JSONArray(request.failures.map { JSONObject().put("id", it.id).put("error", it.reason).put("permanent", it.permanent) }))
        }
        // Порт чат-сервера, позывной и фракция — чтобы сервер мог подсказать другим, где меня искать (адрес он видит сам).
        request.presence?.let { body.put("presence", JSONObject(it)) }
        val httpRequest = Request.Builder()
            .url("$baseUrl/api/changes")
            .post(body.toString().toRequestBody(JSON))
            .withGameSecret(endpoint.secret)
            .build()
        val started = System.currentTimeMillis()
        try {
            http.newCall(httpRequest).execute().use { response ->
                if (!response.isSuccessful) {
                    Mb10Log.warnEvent(TAG, "sync.http_error", "url" to baseUrl, "code" to response.code, "records" to records.size, "ms" to (System.currentTimeMillis() - started))
                    return@withContext null
                }
                val json = JSONObject(response.body?.string().orEmpty())
                val accepted = json.getJSONArray("accepted").let { arr -> (0 until arr.length()).map { arr.getString(it) }.toSet() }
                val rejected = json.getJSONArray("rejected").let { arr ->
                    (0 until arr.length()).associate { i ->
                        val item = arr.getJSONObject(i)
                        item.getString("id") to item.optString("error", "")
                    }
                }
                val pending = json.getJSONArray("pending").let { arr -> (0 until arr.length()).map { arr.getJSONObject(it).toChangeRecord() } }
                val peers = json.optJSONArray("peers")?.let { arr ->
                    (0 until arr.length()).mapNotNull { i ->
                        val o = arr.getJSONObject(i)
                        val host = o.optString("host")
                        val port = o.optInt("port", 0)
                        if (host.isBlank() || port <= 0) null
                        else PeerInfo(o.optString("pubKeyB64"), o.optString("callsign"), o.optString("faction"), host, port)
                    }
                }.orEmpty()
                Mb10Log.event(TAG, "sync.ok", "sent" to records.size, "accepted" to accepted.size, "rejected" to rejected.size, "pendingFromMaster" to pending.size, "peersFromServer" to peers.size, "ms" to (System.currentTimeMillis() - started))
                SyncResponse(accepted, rejected, pending, peers)
            }
        } catch (e: IOException) {
            Mb10Log.warnEvent(TAG, "sync.unreachable", "url" to baseUrl, "error" to e.javaClass.simpleName, "msg" to e.message, "records" to records.size, "ms" to (System.currentTimeMillis() - started))
            null
        } catch (e: JSONException) {
            // 200 с не-JSON телом (прокси, captive portal, не тот сервер по адресу) — раньше это
            // исключение не ловилось и навсегда останавливало цикл синка до перезапуска приложения.
            Mb10Log.warnEvent(TAG, "sync.bad_response", "url" to baseUrl, "msg" to e.message)
            null
        }
    }

    /**
     * POST /api/slots/:slotRef/claim — серверный арбитраж тиражного лута
     * (§5 ТЗ, упрощённая версия). true — слот выдан, false — исчерпан или
     * коллектор недоступен; в обоих случаях вызывающая сторона (см.
     * SlotClaimStore) не должна выдавать уникальный слот на этом пути.
     */
    suspend fun claimSlot(baseUrl: String, slotRef: String, claimantKeyB64: String, claimedAt: Long, signature: String, gameSecret: String? = null): Boolean =
        withContext(Dispatchers.IO) {
            val body = JSONObject()
                .put("claimantKeyB64", claimantKeyB64)
                .put("claimedAt", claimedAt)
                .put("signature", signature)
            val request = Request.Builder()
                .url("$baseUrl/api/slots/${java.net.URLEncoder.encode(slotRef, "UTF-8")}/claim")
                .post(body.toString().toRequestBody(JSON))
                .withGameSecret(gameSecret)
                .build()
            try {
                http.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        Mb10Log.warnEvent(TAG, "slot.claim_http_error", "slot" to slotRef, "code" to response.code)
                        return@withContext false
                    }
                    val granted = JSONObject(response.body?.string().orEmpty()).optBoolean("granted", false)
                    Mb10Log.event(TAG, "slot.claim", "slot" to slotRef, "granted" to granted)
                    granted
                }
            } catch (e: IOException) {
                Mb10Log.warnEvent(TAG, "slot.claim_unreachable", "slot" to slotRef, "error" to e.javaClass.simpleName, "msg" to e.message)
                false
            }
        }
}

/** Заголовок X-Game-Secret — только если мастер задал GAME_SECRET на сервере и раздал его игрокам (см. admin-web/README.md); пусто — ничего не меняется, как раньше. */
private fun Request.Builder.withGameSecret(gameSecret: String?): Request.Builder =
    if (gameSecret.isNullOrBlank()) this else header("X-Game-Secret", gameSecret)

private fun ChangeRecord.toJson(): JSONObject = JSONObject()
    .put("id", id)
    .put("subjectKeyB64", subjectKeyB64)
    .put("seq", seq)
    .put("happenedAt", happenedAt)
    .put("field", field)
    .put("oldValue", oldValue)
    .put("newValue", newValue)
    .put("reason", reason)
    .put("sourceRef", sourceRef)
    .put("actor", actor)
    .put("signature", signature)

private fun JSONObject.toChangeRecord(): ChangeRecord = ChangeRecord(
    id = getString("id"),
    subjectKeyB64 = getString("subjectKeyB64"),
    seq = getLong("seq"),
    happenedAt = getLong("happenedAt"),
    field = getString("field"),
    oldValue = if (isNull("oldValue")) null else optString("oldValue"),
    newValue = if (isNull("newValue")) null else optString("newValue"),
    reason = getString("reason"),
    sourceRef = if (isNull("sourceRef")) null else optString("sourceRef"),
    actor = getString("actor"),
    signature = optString("signature"),
)
