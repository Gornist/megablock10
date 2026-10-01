package com.megablok10.app.items

import com.megablok10.app.breach.Daemon
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.ShardPayload

/**
 * Предмет целиком в том виде, в каком он едет в карточке передачи (Mb10Qr.ItemTransfer.payload)
 * и лежит в журнале отправителя. Формат — в общем модуле правил ([ItemPayloadCodec]); здесь только
 * перевод между Mb10Qr.Shard приложения и [ShardPayload].
 */
object ItemPayload {
    fun encodeShard(shard: Mb10Qr.Shard): String = ItemPayloadCodec.encodeShard(
        ShardPayload(
            shard.id, shard.decryptAction, shard.tier, shard.valueHint, shard.title, shard.meta, shard.body,
            shard.moneyAmount, shard.decrypted
        )
    )

    fun decodeShard(payload: String): Mb10Qr.Shard? = ItemPayloadCodec.decodeShard(payload)?.let {
        Mb10Qr.Shard(
            id = it.id, decryptAction = it.decryptAction, tier = it.tier, valueHint = it.valueHint, title = it.title,
            meta = it.meta, body = it.body, moneyAmount = it.moneyAmount, decrypted = it.decrypted
        )
    }

    fun encodeDaemon(daemon: Daemon): String = ItemPayloadCodec.encodeDaemon(daemon)

    fun decodeDaemon(payload: String): Daemon? = ItemPayloadCodec.decodeDaemon(payload)
}
