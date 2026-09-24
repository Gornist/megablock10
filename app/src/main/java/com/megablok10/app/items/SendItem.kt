package com.megablok10.app.items

import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.deliverCard
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec

/** Что передаём: шард — по id из коллекции, демон — целиком (карточка несёт его содержимое). */
sealed interface OutgoingItem {
    data class Shard(val shardId: String) : OutgoingItem
    data class Daemon(val daemon: com.megablok10.app.breach.Daemon) : OutgoingItem
}

/**
 * Сценарий «передать предмет игроку» — из Кибердеки, из треда чата и со стенда e2e, по тому же протоколу, что и деньги
 * ([com.megablok10.app.wallet.SendPayment]): предмет уходит из коллекции сразу (PENDING), карточка — адресату личным сообщением.
 */
class SendItem(private val ledger: ItemLedger, private val messenger: DirectMessenger) {
    /** Карточка передачи или null — предмета уже нет, он не передаётся (стартовый демон) или адресат — сам игрок. */
    suspend operator fun invoke(me: Identity, item: OutgoingItem, toPubKeyB64: String, offline: Boolean = false): Mb10Qr.ItemTransfer? {
        val card = when (item) {
            is OutgoingItem.Shard -> ledger.sendShard(me, item.shardId, toPubKeyB64)
            is OutgoingItem.Daemon -> ledger.sendDaemon(me, item.daemon, toPubKeyB64)
        } ?: return null
        messenger.deliverCard(me, toPubKeyB64, Mb10QrCodec.encodeItemTransfer(card), offline) { willSend, send ->
            ledger.deliverOutgoing(card.id, willSend, send)
        }
        return card
    }
}
