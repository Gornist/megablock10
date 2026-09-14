package com.megablok10.app.qr

/**
 * Единая точка разбора ВСЕХ QR-кодов игры. Тип определяется по второму
 * сегменту после "MB10" — остальные экраны не парсят сырую строку сами,
 * а получают уже типизированный результат отсюда. Новый тип QR (Container,
 * подписанная транзакция, установка импланта у риппердока) добавляется
 * одним новым вариантом sealed-интерфейса и одной веткой в decode().
 */
sealed interface Mb10Qr {
    data class Contact(
        val publicKeyB64: String,
        val callsign: String,
        val faction: String
    ) : Mb10Qr
}

object Mb10QrCodec {
    private const val MAGIC = "MB10"

    fun decode(raw: String): Mb10Qr? {
        val parts = raw.split(":")
        if (parts.size < 2 || parts[0] != MAGIC) return null
        return when (parts[1]) {
            "CONTACT" -> decodeContact(parts)
            else -> null
        }
    }

    fun encodeContact(publicKeyB64: String, callsign: String, faction: String): String =
        "$MAGIC:CONTACT:v1:$publicKeyB64:$callsign:$faction"

    private fun decodeContact(parts: List<String>): Mb10Qr.Contact? {
        if (parts.size < 6) return null
        return Mb10Qr.Contact(
            publicKeyB64 = parts[3],
            callsign = parts[4],
            faction = parts[5]
        )
    }
}
