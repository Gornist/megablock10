package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

/** Личное сообщение чата на проводе (`MB10CHAT`): карточки и чеки телефонов ездят его телом. Формат — как `app/chat/ChatProtocol`. */
data class ChatDm(
    val from: String,
    val fromCallsign: String,
    val fromFaction: String,
    val to: String,
    val timestamp: Long,
    val body: String,
)

/** Карточка передачи предмета (`MB10:ITEM:v2`), формат и байты подписи — как `app/qr/Mb10QrCodec`. */
data class ItemCard(val id: String, val from: String, val to: String, val kind: String, val payload: String, val signature: String)

/** Денежная карточка (`MB10:TX:v2`) — выдача эдди добычи от ключа мира. */
data class MoneyCard(val id: String, val from: String, val to: String, val amount: Long, val memo: String, val signature: String)

/** Чек получателя (`MB10:RCPT:v1`): подпись над `id|ключ` (kit HandoverRules.receiptSignaturePayload). */
data class ReceiptCard(val id: String, val receiver: String, val signature: String)

/**
 * Запрос входа в Сеть (протокол Моста, раздел 8): телефон сдал карточки предметов и просит собрать из них деку. Подписан
 * ключом игрока. Строка `MB10ENTER:v1:…` — формат Моста, в `WireVersion` приложения его пока нет (его заведёт M3).
 */
data class EnterRequest(
    val rid: String,
    val terminal: String,
    val runner: String,
    val callsign: String,
    val transfers: List<String>,
    val protectedTransfer: String,
    val timestamp: Long,
    val signature: String,
)

/** Ответ Моста на запрос входа, подписан ключом мира: [ok] с [session] либо отказ с [code] и [msg]. */
data class EnterReply(val rid: String, val ok: Boolean, val session: String, val code: String, val msg: String, val signature: String)

/** Кодеки строк, которые Мост меняет с телефонами. Версии и форматы чата и карточек менять нельзя: их читают приложения. */
object PhoneWire {
    private const val CHAT_MAGIC = "MB10CHAT"
    private const val CHAT_VERSION = 1 // = WireVersion.CHAT приложения
    private const val CARD_MAGIC = "MB10"
    const val ENTER_MAGIC = "MB10ENTER"
    const val ENTERED_MAGIC = "MB10ENTERED"
    const val ENTER_VERSION = 1

    private const val CHAT_PARTS = 9
    private const val ITEM_PARTS = 9
    private const val TX_PARTS = 9
    private const val RCPT_PARTS = 6
    private const val ENTER_PARTS = 10
    private const val ENTERED_PARTS = 8

    /** Строка разобрана на части, частей не меньше [min], а первые две — [first] и [second] (или `v<версия>`). */
    private fun List<String>.isShape(min: Int, first: String, second: String): Boolean = size >= min && this[0] == first && this[1] == second

    // ---------- чат ----------

    fun encodeChat(m: ChatDm): String =
        listOf(CHAT_MAGIC, "v$CHAT_VERSION", "DM", m.from, b64(m.fromCallsign), b64(m.fromFaction), m.to, m.timestamp.toString(), b64(m.body))
            .joinToString(":")

    /** Личное сообщение; общий чат фракции и строки других версий — null. */
    fun decodeChat(raw: String): ChatDm? {
        val p = raw.split(":")
        if (!p.isShape(CHAT_PARTS, CHAT_MAGIC, "v$CHAT_VERSION") || p[2] != "DM") return null
        return try {
            ChatDm(p[3], unb64(p[4]), unb64(p[5]), p[6], p[7].toLongOrNull() ?: return null, unb64(p[8]))
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    // ---------- карточки ----------

    fun encodeItem(c: ItemCard): String = "$CARD_MAGIC:ITEM:v2:${c.id}:${c.from}:${c.to}:${c.kind}:${b64(c.payload)}:${c.signature}"

    fun decodeItem(raw: String): ItemCard? {
        val p = raw.split(":")
        if (!p.isShape(ITEM_PARTS, CARD_MAGIC, "ITEM") || p[2] != "v2") return null
        return try {
            ItemCard(p[3], p[4], p[5], p[6], unb64(p[7]), p[8])
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    fun itemSignedBytes(c: ItemCard): ByteArray = "ITEM2|${c.id}|${c.from}|${c.to}|${c.kind}|${c.payload}".toByteArray(Charsets.UTF_8)

    fun encodeMoney(c: MoneyCard): String = "$CARD_MAGIC:TX:v2:${c.id}:${c.from}:${c.to}:${c.amount}:${b64(c.memo)}:${c.signature}"

    fun moneySignedBytes(id: String, from: String, to: String, amount: Long, memo: String): ByteArray =
        "TX2|$id|$from|$to|$amount|$memo".toByteArray(Charsets.UTF_8)

    fun decodeMoney(raw: String): MoneyCard? {
        val p = raw.split(":")
        if (!p.isShape(TX_PARTS, CARD_MAGIC, "TX") || p[2] != "v2") return null
        return try {
            MoneyCard(p[3], p[4], p[5], p[6].toLongOrNull() ?: return null, unb64(p[7]), p[8])
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    fun encodeReceipt(r: ReceiptCard): String = "$CARD_MAGIC:RCPT:v1:${r.id}:${r.receiver}:${r.signature}"

    fun decodeReceipt(raw: String): ReceiptCard? {
        val p = raw.split(":")
        if (!p.isShape(RCPT_PARTS, CARD_MAGIC, "RCPT") || p[2] != "v1") return null
        return ReceiptCard(p[3], p[4], p[5])
    }

    // ---------- вход в Сеть ----------

    fun encodeEnter(r: EnterRequest): String = listOf(
        ENTER_MAGIC, "v$ENTER_VERSION", r.rid, r.terminal, r.runner, b64(r.callsign), r.transfers.joinToString(","),
        r.protectedTransfer, r.timestamp.toString(), r.signature,
    ).joinToString(":")

    fun enterSignedBytes(r: EnterRequest): ByteArray =
        "ENTER1|${r.rid}|${r.terminal}|${r.runner}|${r.callsign}|${r.transfers.joinToString(",")}|${r.protectedTransfer}|${r.timestamp}"
            .toByteArray(Charsets.UTF_8)

    fun decodeEnter(raw: String): EnterRequest? {
        val p = raw.split(":")
        if (!p.isShape(ENTER_PARTS, ENTER_MAGIC, "v$ENTER_VERSION")) return null
        return try {
            EnterRequest(
                p[2], p[3], p[4], unb64(p[5]), p[6].split(",").filter { it.isNotEmpty() }, p[7],
                p[8].toLongOrNull() ?: return null, p[9],
            )
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    fun encodeEntered(r: EnterReply): String = listOf(
        ENTERED_MAGIC, "v$ENTER_VERSION", r.rid, if (r.ok) "1" else "0", b64(r.session), b64(r.code), b64(r.msg), r.signature,
    ).joinToString(":")

    fun enteredSignedBytes(rid: String, ok: Boolean, session: String, code: String, msg: String): ByteArray =
        "ENTERED1|$rid|${if (ok) 1 else 0}|$session|$code|$msg".toByteArray(Charsets.UTF_8)

    fun decodeEntered(raw: String): EnterReply? {
        val p = raw.split(":")
        if (!p.isShape(ENTERED_PARTS, ENTERED_MAGIC, "v$ENTER_VERSION")) return null
        return try {
            EnterReply(p[2], p[3] == "1", unb64(p[4]), unb64(p[5]), unb64(p[6]), p[7])
        } catch (e: IllegalArgumentException) {
            null
        }
    }
}
