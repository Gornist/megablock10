package com.megablok10.app.call

import java.util.Base64

enum class CallSignalType { OFFER, ANSWER, DECLINE, END }

/** Один сигнал звонка на проводе — только сигнализация (кто звонит/принял/сбросил), без самого аудио. */
data class CallSignal(
    val type: CallSignalType,
    val callId: String,
    val fromPubKeyB64: String,
    val fromCallsign: String,
    val toPubKeyB64: String,
    val timestamp: Long
)

/**
 * Тот же построчный принцип, что и у ChatProtocol, с отдельным магическим
 * префиксом — оба вида сообщений идут через один и тот же сокет-сервер
 * (ChatServer), а первым полем строки различается, что перед нами.
 */
object CallProtocol {
    private const val MAGIC = "MB10CALL"

    fun encode(signal: CallSignal): String = listOf(
        MAGIC, "v1", signal.type.name, signal.callId,
        signal.fromPubKeyB64, b64(signal.fromCallsign), signal.toPubKeyB64, signal.timestamp.toString()
    ).joinToString(":")

    fun decode(raw: String): CallSignal? {
        val parts = raw.split(":")
        if (parts.size < 8 || parts[0] != MAGIC) return null
        return try {
            CallSignal(
                type = CallSignalType.valueOf(parts[2]),
                callId = parts[3],
                fromPubKeyB64 = parts[4],
                fromCallsign = unb64(parts[5]),
                toPubKeyB64 = parts[6],
                timestamp = parts[7].toLongOrNull() ?: return null
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun b64(text: String): String = Base64.getEncoder().encodeToString(text.toByteArray(Charsets.UTF_8))

    private fun unb64(text: String): String = String(Base64.getDecoder().decode(text), Charsets.UTF_8)
}
