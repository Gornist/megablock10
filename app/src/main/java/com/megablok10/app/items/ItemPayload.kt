package com.megablok10.app.items

import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.Tier
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

/**
 * Предмет целиком в том виде, в каком он едет в карточке передачи (Mb10Qr.ItemTransfer.payload)
 * и лежит в журнале отправителя, чтобы отменённая передача вернула его без потерь. Поля через '|',
 * свободный текст в base64 — тот же стиль, что у LootCodec. Для шарда переносится и состояние
 * «расшифрован»: расшифрованный шард остаётся открытым у нового владельца.
 */
object ItemPayload {
    fun encodeShard(shard: Mb10Qr.Shard): String = listOf(
        "SHARD", shard.id, if (shard.decryptAction) "1" else "0", shard.tier.toString(), b64(shard.valueHint),
        b64(shard.title), b64(shard.meta), b64(shard.body), shard.moneyAmount.toString(), if (shard.decrypted) "1" else "0"
    ).joinToString("|")

    fun decodeShard(payload: String): Mb10Qr.Shard? = try {
        val p = payload.split("|")
        if (p.size < 10 || p[0] != "SHARD") null
        else Mb10Qr.Shard(
            id = p[1], decryptAction = p[2] == "1", tier = p[3].toInt(), valueHint = unb64(p[4]), title = unb64(p[5]),
            meta = unb64(p[6]), body = unb64(p[7]), moneyAmount = p[8].toLong(), decrypted = p[9] == "1"
        )
    } catch (e: Exception) {
        null
    }

    fun encodeDaemon(daemon: Daemon): String =
        listOf("DAEMON", daemon.id, b64(daemon.name), daemon.sequence.joinToString(","), daemon.tier.level.toString(), daemon.effect.name).joinToString("|")

    fun decodeDaemon(payload: String): Daemon? = try {
        val p = payload.split("|")
        val effect = DaemonEffect.entries.find { it.name == p.getOrNull(5) }
        if (p.size < 6 || p[0] != "DAEMON" || effect == null) null
        else Daemon(id = p[1], name = unb64(p[2]), sequence = p[3].split(","), tier = Tier.fromLevel(p[4].toInt()), effect = effect)
    } catch (e: Exception) {
        null
    }
}
