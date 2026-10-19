package com.megablok10.app.collector

import org.json.JSONException
import org.json.JSONObject

/** Пауза по умолчанию, если сервер ответил 429, но не сказал, сколько ждать. */
private const val DEFAULT_RETRY_AFTER_SEC = 60

/**
 * Итог обмена короткого кода на QR персонажа (POST /api/provisions/redeem, docs/provisioning-qr.md). Неизвестный и уже погашенный
 * код сервер не различает намеренно — [UnknownCode] один на оба случая.
 */
sealed interface RedeemResult {
    /** Строка QR как с экрана мастера (`MB10:PROV:v1:…`) — дальше обычная выдача. */
    data class Qr(val qr: String) : RedeemResult
    data object UnknownCode : RedeemResult
    /** Лимит по адресу или общий потолок сервера — для игрока это одно и то же. */
    data class RateLimited(val retryAfterSec: Int) : RedeemResult
    /** Старый сервер без маршрута (404 без тела ошибки), чужой сервер по адресу или битый ответ. */
    data object Unsupported : RedeemResult
    /** Сети нет или сервер по адресу не отвечает. */
    data object Unreachable : RedeemResult
}

/**
 * Разбор ответа сервера без сети — чтобы каждый случай проверялся тестом. 404 считается «неизвестным кодом» только с телом
 * `{"error":"unknown_code"}`: просто 404 — это сервер, которому маршрут неизвестен (старая версия), и говорить «код неверный» было бы ложью.
 */
fun parseRedeemResponse(httpCode: Int, body: String, retryAfterHeader: String?): RedeemResult {
    val json = try {
        JSONObject(body)
    } catch (e: JSONException) {
        null
    }
    return when (httpCode) {
        200 -> json?.optString("qr", "")?.takeIf { it.isNotBlank() }?.let { RedeemResult.Qr(it) } ?: RedeemResult.Unsupported
        404 -> if (json?.optString("error") == "unknown_code") RedeemResult.UnknownCode else RedeemResult.Unsupported
        429 -> {
            val fromBody = json?.optInt("retryAfterSec", 0)?.takeIf { it > 0 }
            val fromHeader = retryAfterHeader?.trim()?.toIntOrNull()?.takeIf { it > 0 }
            RedeemResult.RateLimited(fromBody ?: fromHeader ?: DEFAULT_RETRY_AFTER_SEC)
        }
        else -> RedeemResult.Unsupported
    }
}
