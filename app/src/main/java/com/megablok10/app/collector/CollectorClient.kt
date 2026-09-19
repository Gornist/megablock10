package com.megablok10.app.collector

import android.util.Log
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

data class BatchResult(
    val accepted: Set<String>,
    val rejected: Map<String, String>,
    val pending: List<ChangeRecord>,
)

/**
 * HTTP-клиент до мастерского коллектора (admin-web/server) — обычный POST
 * в открытой локальной сети, без TLS (см. network_security_config.xml).
 * Не P2P: в отличие от ChatServer/ClaimClient это единственное место в
 * приложении, где устройство говорит с фиксированным сервером, а не с
 * другими игроками напрямую.
 */
object CollectorClient {
    private val http = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build()

    /**
     * POST /api/changes — см. §3.1 ТЗ. null означает "сеть/коллектор
     * недоступны", не "коллектор отбраковал всё". subjectKeyB64 передаётся
     * ВСЕГДА, даже при пустом records — этим же запросом сервер отдаёт
     * накопленные MASTER_OVERRIDE для этого ключа (§6.3), а без явного
     * ключа в пустом батче ему неоткуда узнать, чью очередь проверять.
     */
    suspend fun sendBatch(
        baseUrl: String,
        records: List<ChangeRecord>,
        subjectKeyB64: String?,
        gameSecret: String? = null,
        ackIds: List<String> = emptyList(),
    ): BatchResult? = withContext(Dispatchers.IO) {
        val body = JSONObject().put("records", JSONArray(records.map { it.toJson() }))
        if (subjectKeyB64 != null) body.put("subjectKeyB64", subjectKeyB64)
        // Подтверждение применённых правок мастера из прошлого ответа — сервер шлёт их снова, пока не получит ack.
        if (ackIds.isNotEmpty()) body.put("ackIds", JSONArray(ackIds))
        val request = Request.Builder()
            .url("$baseUrl/api/changes")
            .post(body.toString().toRequestBody(JSON))
            .withGameSecret(gameSecret)
            .build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "POST /api/changes -> ${response.code}")
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
                BatchResult(accepted, rejected, pending)
            }
        } catch (e: IOException) {
            Log.w(TAG, "коллектор недоступен: ${e.message}")
            null
        } catch (e: JSONException) {
            // 200 с не-JSON телом (прокси, captive portal, не тот сервер по адресу) — раньше это
            // исключение не ловилось и навсегда останавливало цикл синка до перезапуска приложения.
            Log.w(TAG, "коллектор ответил не тем, что ожидалось: ${e.message}")
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
                    if (!response.isSuccessful) return@withContext false
                    JSONObject(response.body?.string().orEmpty()).optBoolean("granted", false)
                }
            } catch (e: IOException) {
                Log.w(TAG, "коллектор недоступен при заявке на слот: ${e.message}")
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
