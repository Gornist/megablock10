package com.megablok10.app.chat

import com.megablok10.app.net.WireVersion
import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

enum class ChatMessageType { FACTION, DM }

/** Одно сообщение на проводе — то же самое, что ляжет в Room после приёма/отправки. */
data class ChatWireMessage(
    val type: ChatMessageType,
    val fromPubKeyB64: String,
    val fromCallsign: String,
    val fromFaction: String,
    val toPubKeyB64: String,
    val timestamp: Long,
    val body: String
)

/**
 * Построчный протокол поверх голого TCP-сокета — тот же принцип, что и у
 * Mb10QrCodec: свободный текст (позывной, фракция, текст сообщения) через
 * base64, чтобы двоеточия и переносы строк в тексте не ломали разбор одной
 * строки. Одно TCP-соединение = одно сообщение (открыли, отправили строку,
 * закрыли) — для чата с редкими сообщениями это проще, чем держать открытые
 * сокеты, и не требует отдельного протокола keep-alive.
 */
object ChatProtocol {
    private const val MAGIC = "MB10CHAT"

    fun encode(message: ChatWireMessage): String = listOf(
        MAGIC, "v${WireVersion.CHAT}", message.type.name,
        message.fromPubKeyB64, b64(message.fromCallsign), b64(message.fromFaction),
        message.toPubKeyB64, message.timestamp.toString(), b64(message.body)
    ).joinToString(":")

    fun decode(raw: String): ChatWireMessage? {
        val parts = raw.split(":")
        if (parts.size < 9 || !WireVersion.matches(parts, MAGIC)) return null
        return try {
            ChatWireMessage(
                type = ChatMessageType.valueOf(parts[2]),
                fromPubKeyB64 = parts[3],
                fromCallsign = unb64(parts[4]),
                fromFaction = unb64(parts[5]),
                toPubKeyB64 = parts[6],
                timestamp = parts[7].toLongOrNull() ?: return null,
                body = unb64(parts[8])
            )
        } catch (e: Exception) {
            null
        }
    }
}
