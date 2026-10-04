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
 * ключом игрока. Строки `MB10ENTER:v1:…` и `MB10ENTER:v2:…` (с RAM) — близнец `NetrunWire` приложения. [ram] — RAM персонажа из v2;
 * `null` — запрос v1 (телефон проверил деку против своей RAM, Мост её не знает).
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
    val ram: Int? = null,
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
    const val ENTER_VERSION = 1 // запрос входа v1 и ответ `MB10ENTERED` (его версия не менялась)
    const val ENTER_VERSION_RAM = 2 // запрос входа v2: с RAM

    private const val CHAT_PARTS = 9
    private const val ITEM_PARTS = 9
    private const val TX_PARTS = 9
    private const val RCPT_PARTS = 6
    private const val ENTER_PARTS = 10
    private const val ENTER_RAM_PARTS = 11
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

    // ---------- сигнал СБ ----------

    /** Сообщение фракции (`MB10CHAT … FACTION`): ровно то, что собирает `ChatProtocol.encode` приложения для `sendFaction`. */
    fun encodeFactionChat(from: String, callsign: String, faction: String, timestamp: Long, body: String): String =
        listOf(CHAT_MAGIC, "v$CHAT_VERSION", "FACTION", from, b64(callsign), b64(faction), "", timestamp.toString(), b64(body)).joinToString(":")

    /** Тело сигнала СБ (`MB10:SECALERT:v1`) — как `Mb10QrCodec.encodeSecurityAlert`; позывной и точное время — null, если не раскрываются. */
    fun encodeSecAlert(containerId: String, containerName: String, tier: Int, callsign: String?, preciseAt: Long?): String =
        listOf(CARD_MAGIC, "SECALERT", "v1", containerId, b64(containerName), tier.toString(), callsign?.let { b64(it) } ?: "", preciseAt?.toString() ?: "")
            .joinToString(":")

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

    /** Строка запроса: без [EnterRequest.ram] — v1 (10 частей), с ним — v2 (11 частей, `ram` перед `ts`). */
    fun encodeEnter(r: EnterRequest): String {
        val head = listOf(ENTER_MAGIC, "v${if (r.ram == null) ENTER_VERSION else ENTER_VERSION_RAM}", r.rid, r.terminal, r.runner, b64(r.callsign), r.transfers.joinToString(","), r.protectedTransfer)
        return (head + listOfNotNull(r.ram?.toString()) + listOf(r.timestamp.toString(), r.signature)).joinToString(":")
    }

    /** Байты подписи: v1 — `ENTER1|…`, v2 — `ENTER2|…|<ram>|…` (подпись v1 нельзя выдать за v2). */
    fun enterSignedBytes(r: EnterRequest): ByteArray {
        val common = "${r.rid}|${r.terminal}|${r.runner}|${r.callsign}|${r.transfers.joinToString(",")}|${r.protectedTransfer}"
        val text = if (r.ram == null) "ENTER1|$common|${r.timestamp}" else "ENTER2|$common|${r.ram}|${r.timestamp}"
        return text.toByteArray(Charsets.UTF_8)
    }

    /** Запрос входа v1 или v2; другая версия, нехватка частей, не число в `ram` или `ts` — null. */
    fun decodeEnter(raw: String): EnterRequest? {
        val p = raw.split(":")
        val v2 = p.isShape(ENTER_RAM_PARTS, ENTER_MAGIC, "v$ENTER_VERSION_RAM")
        if (!v2 && !p.isShape(ENTER_PARTS, ENTER_MAGIC, "v$ENTER_VERSION")) return null
        return try {
            val ram = if (v2) p[8].toIntOrNull() ?: return null else null
            val tail = if (v2) 1 else 0
            EnterRequest(
                p[2], p[3], p[4], unb64(p[5]), p[6].split(",").filter { it.isNotEmpty() }, p[7],
                p[8 + tail].toLongOrNull() ?: return null, p[9 + tail], ram,
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
