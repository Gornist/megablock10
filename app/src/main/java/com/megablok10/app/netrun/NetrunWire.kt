package com.megablok10.app.netrun

import com.megablok10.app.net.WireVersion
import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

/**
 * Запрос входа в «Сеть» (docs/netrun-bridge-protocol.md, раздел 8): телефон сдал карточки предметов ([transfers] — id карточек
 * `SendItem`) и просит собрать из них деку на терминале [terminal]. [protectedTransfer] — карточка демона из защищённого слота.
 * Подписан ключом игрока [runner].
 */
data class EnterRequest(
    val rid: String,
    val terminal: String,
    val runner: String,
    val callsign: String,
    val transfers: List<String>,
    val protectedTransfer: String,
    val timestamp: Long,
    val signature: String = "",
)

/** Ответ Моста на запрос входа, подписан ключом мира: [ok] с [session] либо отказ с [code] и [msg]. */
data class EnterReply(val rid: String, val ok: Boolean, val session: String, val code: String, val msg: String, val signature: String)

/**
 * Строки входа в «Сеть»: `MB10ENTER:v1:<rid>:<терминал>:<ключ>:<b64 позывной>:<transfers через запятую>:<protected>:<ts>:<подпись>` и
 * `MB10ENTERED:v1:<rid>:<1|0>:<b64 сессия>:<b64 code>:<b64 msg>:<подпись>`. Формат — близнец `PhoneWire` Моста (`netrun-bridge`):
 * менять только вместе с ним и с версией в [WireVersion].
 */
object NetrunWire {
    private const val ENTER_MAGIC = "MB10ENTER"
    private const val ENTERED_MAGIC = "MB10ENTERED"
    private const val ENTER_PARTS = 10
    private const val ENTERED_PARTS = 8

    fun encodeEnter(r: EnterRequest): String = listOf(
        ENTER_MAGIC, "v${WireVersion.ENTER}", r.rid, r.terminal, r.runner, b64(r.callsign), r.transfers.joinToString(","),
        r.protectedTransfer, r.timestamp.toString(), r.signature,
    ).joinToString(":")

    /** Байты, которые подписывает игрок и проверяет Мост. */
    fun enterSignedBytes(r: EnterRequest): ByteArray =
        "ENTER1|${r.rid}|${r.terminal}|${r.runner}|${r.callsign}|${r.transfers.joinToString(",")}|${r.protectedTransfer}|${r.timestamp}"
            .toByteArray(Charsets.UTF_8)

    fun decodeEnter(raw: String): EnterRequest? {
        val p = raw.split(":")
        if (p.size < ENTER_PARTS || !WireVersion.matches(p, ENTER_MAGIC)) return null
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
        ENTERED_MAGIC, "v${WireVersion.ENTERED}", r.rid, if (r.ok) "1" else "0", b64(r.session), b64(r.code), b64(r.msg), r.signature,
    ).joinToString(":")

    /** Байты, которые подписывает Мост (ключ мира) и проверяет телефон. */
    fun enteredSignedBytes(rid: String, ok: Boolean, session: String, code: String, msg: String): ByteArray =
        "ENTERED1|$rid|${if (ok) 1 else 0}|$session|$code|$msg".toByteArray(Charsets.UTF_8)

    fun enteredSignedBytes(r: EnterReply): ByteArray = enteredSignedBytes(r.rid, r.ok, r.session, r.code, r.msg)

    fun decodeEntered(raw: String): EnterReply? {
        val p = raw.split(":")
        if (p.size < ENTERED_PARTS || !WireVersion.matches(p, ENTERED_MAGIC)) return null
        return try {
            EnterReply(p[2], p[3] == "1", unb64(p[4]), unb64(p[5]), unb64(p[6]), p[7])
        } catch (e: IllegalArgumentException) {
            null
        }
    }
}
