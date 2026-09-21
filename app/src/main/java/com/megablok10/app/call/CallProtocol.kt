package com.megablok10.app.call

import java.util.Base64
import com.megablok10.app.net.WireVersion

enum class CallSignalType { OFFER, ANSWER, ICE_CANDIDATE, DECLINE, END }

/**
 * Один сигнал звонка на проводе. sdp — только у OFFER/ANSWER (сама SDP-строка
 * WebRTC), iceSdpMid/iceSdpMLineIndex/iceCandidate — только у ICE_CANDIDATE;
 * у остальных типов (DECLINE/END, старое чистое "рингую"-OFFER до звонков) всё
 * это null, в проводе просто пустые поля.
 */
data class CallSignal(
    val type: CallSignalType,
    val callId: String,
    val fromPubKeyB64: String,
    val fromCallsign: String,
    val toPubKeyB64: String,
    val timestamp: Long,
    val sdp: String? = null,
    val iceSdpMid: String? = null,
    val iceSdpMLineIndex: Int? = null,
    val iceCandidate: String? = null
)

/**
 * Тот же построчный принцип, что и у ChatProtocol, с отдельным магическим
 * префиксом — оба вида сообщений идут через один и тот же сокет-сервер
 * (ChatServer), а первым полем строки различается, что перед нами. SDP и
 * ICE-кандидаты — свободный текст (переносы строк, двоеточия), поэтому тоже
 * через base64, как позывной/фракция/тело сообщения в остальном протоколе.
 */
object CallProtocol {
    private const val MAGIC = "MB10CALL"

    fun encode(signal: CallSignal): String = listOf(
        MAGIC, "v${WireVersion.CALL}", signal.type.name, signal.callId,
        signal.fromPubKeyB64, b64(signal.fromCallsign), signal.toPubKeyB64, signal.timestamp.toString(),
        b64(signal.sdp ?: ""), b64(signal.iceSdpMid ?: ""), (signal.iceSdpMLineIndex ?: -1).toString(), b64(signal.iceCandidate ?: "")
    ).joinToString(":")

    fun decode(raw: String): CallSignal? {
        val parts = raw.split(":")
        if (parts.size < 12 || !WireVersion.matches(parts, MAGIC)) return null
        return try {
            CallSignal(
                type = CallSignalType.valueOf(parts[2]),
                callId = parts[3],
                fromPubKeyB64 = parts[4],
                fromCallsign = unb64(parts[5]),
                toPubKeyB64 = parts[6],
                timestamp = parts[7].toLongOrNull() ?: return null,
                sdp = unb64(parts[8]).ifEmpty { null },
                iceSdpMid = unb64(parts[9]).ifEmpty { null },
                iceSdpMLineIndex = parts[10].toIntOrNull()?.takeIf { it >= 0 },
                iceCandidate = unb64(parts[11]).ifEmpty { null }
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun b64(text: String): String = Base64.getEncoder().encodeToString(text.toByteArray(Charsets.UTF_8))

    private fun unb64(text: String): String = String(Base64.getDecoder().decode(text), Charsets.UTF_8)
}
