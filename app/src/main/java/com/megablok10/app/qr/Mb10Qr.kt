package com.megablok10.app.qr

import java.util.Base64

/**
 * Единая точка разбора ВСЕХ QR-кодов игры. Тип определяется по второму
 * сегменту после "MB10" — остальные экраны не парсят сырую строку сами,
 * а получают уже типизированный результат отсюда. Новый тип QR (Container,
 * установка импланта у риппердока) добавляется одним новым вариантом
 * sealed-интерфейса и одной веткой в decode().
 *
 * Свободный текст (позывной, имя точки, текст шарда) кодируется в base64,
 * а не пишется как есть между двоеточиями — иначе любой ":" внутри текста
 * автора QR-кода (мастера игры) сломал бы разбор.
 */
sealed interface Mb10Qr {
    data class Contact(
        val publicKeyB64: String,
        val callsign: String,
        val faction: String
    ) : Mb10Qr

    /** Точка доступа для Breach Protocol — печатается мастерами на месте. */
    data class AccessPoint(
        val id: String,
        val name: String
    ) : Mb10Qr

    /** Шард — печатается мастерами на месте либо выдаётся как награда за взлом. */
    data class Shard(
        val id: String,
        val badge: String,
        val decryptAction: Boolean,
        val title: String,
        val meta: String,
        val body: String
    ) : Mb10Qr

    /**
     * Подписанная денежная транзакция. Плательщик генерирует и показывает
     * QR — деньги у него списываются сразу в момент генерации (как передача
     * наличных из рук в руки), получатель сканирует и зачисляет их себе.
     * fromPubKeyB64 — тот же ключ, что и в Contact, подпись проверяется им же.
     */
    data class Transaction(
        val id: String,
        val fromPubKeyB64: String,
        val amount: Long,
        val memo: String,
        val signatureB64: String
    ) : Mb10Qr

    /**
     * Подтверждение получения — показывает получатель в ответ, отправитель
     * сканирует его, чтобы зафиксировать транзакцию (см. TransactionStore).
     * До этого момента отправитель ещё может отменить платёж и вернуть себе
     * деньги; после — нет, ровно для того, чтобы "отменить и оставить деньги
     * себе" было невозможно, если получатель уже реально получил перевод.
     */
    data class Receipt(
        val id: String,
        val receiverPubKeyB64: String,
        val signatureB64: String
    ) : Mb10Qr
}

object Mb10QrCodec {
    private const val MAGIC = "MB10"

    fun decode(raw: String): Mb10Qr? {
        val parts = raw.split(":")
        if (parts.size < 2 || parts[0] != MAGIC) return null
        return try {
            when (parts[1]) {
                "CONTACT" -> decodeContact(parts)
                "AP" -> decodeAccessPoint(parts)
                "SHARD" -> decodeShard(parts)
                "TX" -> decodeTransaction(parts)
                "RCPT" -> decodeReceipt(parts)
                else -> null
            }
        } catch (e: Exception) {
            null
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

    fun encodeAccessPoint(id: String, name: String): String =
        "$MAGIC:AP:v1:$id:${b64(name)}"

    private fun decodeAccessPoint(parts: List<String>): Mb10Qr.AccessPoint? {
        if (parts.size < 5) return null
        return Mb10Qr.AccessPoint(id = parts[3], name = unb64(parts[4]))
    }

    fun encodeShard(
        id: String,
        badge: String,
        decryptAction: Boolean,
        title: String,
        meta: String,
        body: String
    ): String = "$MAGIC:SHARD:v1:$id:$badge:${if (decryptAction) 1 else 0}:${b64(title)}:${b64(meta)}:${b64(body)}"

    private fun decodeShard(parts: List<String>): Mb10Qr.Shard? {
        if (parts.size < 9) return null
        return Mb10Qr.Shard(
            id = parts[3],
            badge = parts[4],
            decryptAction = parts[5] == "1",
            title = unb64(parts[6]),
            meta = unb64(parts[7]),
            body = unb64(parts[8])
        )
    }

    fun encodeTransaction(tx: Mb10Qr.Transaction): String =
        "$MAGIC:TX:v1:${tx.id}:${tx.fromPubKeyB64}:${tx.amount}:${b64(tx.memo)}:${tx.signatureB64}"

    private fun decodeTransaction(parts: List<String>): Mb10Qr.Transaction? {
        if (parts.size < 8) return null
        val amount = parts[5].toLongOrNull() ?: return null
        return Mb10Qr.Transaction(
            id = parts[3],
            fromPubKeyB64 = parts[4],
            amount = amount,
            memo = unb64(parts[6]),
            signatureB64 = parts[7]
        )
    }

    /** Байты, которые подписывает плательщик и проверяет получатель — одна и та же формула по обе стороны. */
    fun transactionSignaturePayload(id: String, fromPubKeyB64: String, amount: Long, memo: String): ByteArray =
        "$id|$fromPubKeyB64|$amount|$memo".toByteArray(Charsets.UTF_8)

    fun encodeReceipt(receipt: Mb10Qr.Receipt): String =
        "$MAGIC:RCPT:v1:${receipt.id}:${receipt.receiverPubKeyB64}:${receipt.signatureB64}"

    private fun decodeReceipt(parts: List<String>): Mb10Qr.Receipt? {
        if (parts.size < 6) return null
        return Mb10Qr.Receipt(id = parts[3], receiverPubKeyB64 = parts[4], signatureB64 = parts[5])
    }

    /** Байты, которые подписывает получатель на чеке — та же id, что и у исходной транзакции, плюс его ключ. */
    fun receiptSignaturePayload(id: String, receiverPubKeyB64: String): ByteArray =
        "$id|$receiverPubKeyB64".toByteArray(Charsets.UTF_8)

    private fun b64(text: String): String = Base64.getEncoder().encodeToString(text.toByteArray(Charsets.UTF_8))

    private fun unb64(text: String): String = String(Base64.getDecoder().decode(text), Charsets.UTF_8)
}
