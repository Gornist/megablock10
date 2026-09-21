package com.megablok10.app.items

import android.content.Context
import androidx.room.withTransaction
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.MockBreach
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.ItemTransferEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.SendOutcome
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Передача шардов и демонов между игроками — тот же протокол, что у денег (см. TransactionStore):
 * предмет уходит из коллекции отправителя сразу (PENDING), карточка доставляется получателю
 * (DELIVERED — с этого момента отмена запрещена), получатель нажимает «Принять» и шлёт чек (CONFIRMED).
 * Предметы не копируются, а именно передаются: у получателя они появляются только при принятии,
 * у отправителя пропадают при отправке, отмена недоставленной передачи возвращает предмет.
 */
private const val TAG = "Items"

object ItemTransferStore {
    fun observeAll(context: Context): Flow<List<ItemTransferEntity>> =
        Mb10Database.get(context).itemTransferDao().observeAll()

    /** Стартовый демон есть у каждого персонажа и пересеивается при пустой коллекции — передавать его нельзя, иначе он размножался бы. */
    fun isTransferable(daemon: Daemon): Boolean = MockBreach.daemons.none { it.id == daemon.id }

    // Проверка «предмет ещё у меня» и его списание — одной транзакцией: иначе двойной тап по «Передать» создавал бы две передачи одного предмета.
    suspend fun sendShard(context: Context, identity: Identity, shardId: String, toPubKeyB64: String): Mb10Qr.ItemTransfer? =
        Mb10Database.get(context).withTransaction {
            val entity = Mb10Database.get(context).shardDao().get(shardId) ?: return@withTransaction null
            val shard = Mb10Qr.Shard(entity.id, entity.decryptAction, entity.tier, entity.valueHint, entity.title, entity.meta, entity.body, entity.moneyAmount, entity.decrypted)
            sendOut(context, identity, ItemKind.SHARD, ItemPayload.encodeShard(shard), toPubKeyB64) { id ->
                ShardStore.remove(context, shardId, ChangeReason.ITEM_TRANSFER_OUT, sourceRef = id)
            }
        }

    suspend fun sendDaemon(context: Context, identity: Identity, daemon: Daemon, toPubKeyB64: String): Mb10Qr.ItemTransfer? {
        if (!isTransferable(daemon)) return null
        return Mb10Database.get(context).withTransaction {
            if (Mb10Database.get(context).daemonDao().get(daemon.id) == null) return@withTransaction null
            sendOut(context, identity, ItemKind.DAEMON, ItemPayload.encodeDaemon(daemon), toPubKeyB64) { id ->
                DaemonStore.remove(context, daemon.id, ChangeReason.ITEM_TRANSFER_OUT, sourceRef = id)
            }
        }
    }

    private suspend fun sendOut(
        context: Context, identity: Identity, kind: ItemKind, payload: String, toPubKeyB64: String, removeItem: suspend (transferId: String) -> Unit
    ): Mb10Qr.ItemTransfer? {
        if (toPubKeyB64 == identity.publicKeyB64) return null
        val id = "item-${UUID.randomUUID()}"
        val signature = IdentityManager.sign(context, Mb10QrCodec.itemTransferSignaturePayload(id, identity.publicKeyB64, toPubKeyB64, kind, payload))
        val inserted = Mb10Database.get(context).itemTransferDao().insertIfAbsent(
            ItemTransferEntity(id, toPubKeyB64, kind.name, payload, System.currentTimeMillis(), TransactionStatus.PENDING, outgoing = true)
        )
        if (inserted == -1L) return null
        removeItem(id)
        Mb10Log.event(TAG, "item.out_created", "id" to id, "kind" to kind.name, "to" to Mb10Log.short(toPubKeyB64), "payloadChars" to payload.length)
        return Mb10Qr.ItemTransfer(id, identity.publicKeyB64, toPubKeyB64, kind, payload, signature)
    }

    /** Как TransactionStore.deliverOutgoing: DELIVERED ставится ДО отправки, откат — только если соединиться не удалось (NOT_REACHED). */
    suspend fun deliverOutgoing(context: Context, id: String, willSend: Boolean, send: suspend () -> SendOutcome) {
        val dao = Mb10Database.get(context).itemTransferDao()
        if (!willSend) {
            send()
            Mb10Log.event(TAG, "item.deliver", "id" to id, "peerVisible" to false, "status" to "остаётся PENDING")
            return
        }
        dao.markDelivered(id)
        val outcome = send()
        if (outcome == SendOutcome.NOT_REACHED) dao.markUndelivered(id)
        Mb10Log.event(TAG, "item.deliver", "id" to id, "peerVisible" to true, "outcome" to outcome.name, "status" to if (outcome == SendOutcome.NOT_REACHED) "откат в PENDING" else "DELIVERED")
    }

    /** Отмена недоставленной передачи: предмет возвращается в коллекцию. false — карточка уже доставлена/подтверждена или записи нет. */
    suspend fun cancelOutgoing(context: Context, id: String): Boolean {
        val dao = Mb10Database.get(context).itemTransferDao()
        val record = dao.get(id) ?: run { Mb10Log.warnEvent(TAG, "item.cancel", "id" to id, "result" to "нет такой записи"); return false }
        if (!record.outgoing || dao.cancelPending(id) == 0) { Mb10Log.warnEvent(TAG, "item.cancel", "id" to id, "result" to "отказ: уже доставлена/подтверждена"); return false }
        restore(context, record, ChangeReason.ITEM_TRANSFER_CANCELLED)
        Mb10Log.event(TAG, "item.cancel", "id" to id, "result" to "отменена, предмет возвращён", "kind" to record.kind)
        return true
    }

    /** Чек получателя фиксирует передачу — те же проверки, что у денег: чек подписал именно адресат этой передачи. */
    suspend fun verifyAndConfirmReceipt(context: Context, id: String, receipt: Mb10Qr.Receipt): Boolean {
        if (receipt.id != id) return false
        val dao = Mb10Database.get(context).itemTransferDao()
        val record = dao.get(id) ?: return false
        if (!record.outgoing || record.counterpartyPubKeyB64 != receipt.receiverPubKeyB64) return false
        if (!IdentityManager.verify(receipt.receiverPubKeyB64, Mb10QrCodec.receiptSignaturePayload(receipt.id, receipt.receiverPubKeyB64), receipt.signatureB64)) return false
        val confirmed = dao.confirm(id) > 0
        Mb10Log.event(TAG, "item.receipt", "id" to id, "confirmed" to confirmed)
        return confirmed
    }

    /** Получатель проверяет подпись отправителя и кладёт предмет в коллекцию. false — подпись не сошлась, своя же карточка или уже принято. */
    suspend fun acceptIncoming(context: Context, myPubKeyB64: String, card: Mb10Qr.ItemTransfer): Boolean {
        fun reject(why: String): Boolean { Mb10Log.warnEvent(TAG, "item.in_rejected", "id" to card.id, "from" to Mb10Log.short(card.fromPubKeyB64), "kind" to card.kind.name, "why" to why); return false }
        if (card.fromPubKeyB64 == myPubKeyB64) return reject("своя же карточка")
        // Адресат в подписи: чужую копию карточки принять нельзя (иначе один предмет можно получить дважды).
        if (card.toPubKeyB64 != myPubKeyB64) return reject("адресована не мне")
        val signed = Mb10QrCodec.itemTransferSignaturePayload(card.id, card.fromPubKeyB64, card.toPubKeyB64, card.kind, card.payload)
        if (!IdentityManager.verify(card.fromPubKeyB64, signed, card.signatureB64)) return reject("подпись не сошлась")

        val record = ItemTransferEntity(card.id, card.fromPubKeyB64, card.kind.name, card.payload, System.currentTimeMillis(), TransactionStatus.CONFIRMED, outgoing = false)
        // Запись-«принято» ставится первой: если предмет не разобрался, откатываем её, иначе карточка «сгорит» без выдачи.
        if (Mb10Database.get(context).itemTransferDao().insertIfAbsent(record) == -1L) return reject("уже принята раньше")
        if (!restore(context, record, ChangeReason.ITEM_TRANSFER_IN)) {
            Mb10Database.get(context).itemTransferDao().delete(card.id)
            return reject("содержимое не разобралось")
        }
        Mb10Log.event(TAG, "item.in_accepted", "id" to card.id, "from" to Mb10Log.short(card.fromPubKeyB64), "kind" to card.kind.name)
        return true
    }

    /** Отправляет карточку получателю как личное сообщение: сохраняет её в тред, а если он в сети — доставляет и помечает DELIVERED. */
    suspend fun deliver(context: Context, identity: Identity, card: Mb10Qr.ItemTransfer, toPubKeyB64: String) {
        val peer = PresenceService.peers.value.find { it.pubKeyB64 == toPubKeyB64 }
        deliverOutgoing(context, card.id, willSend = peer != null) {
            ChatStore.sendDirectOutcome(context, identity, toPubKeyB64, peer, Mb10QrCodec.encodeItemTransfer(card))
        }
    }

    fun buildReceipt(context: Context, identity: Identity, id: String): Mb10Qr.Receipt = TransactionStore.buildReceipt(context, identity, id)

    /** Кладёт предмет из журнала в коллекцию (принятие у получателя или возврат при отмене у отправителя). */
    private suspend fun restore(context: Context, record: ItemTransferEntity, reason: String): Boolean = when (ItemKind.valueOf(record.kind)) {
        ItemKind.SHARD -> {
            val shard = ItemPayload.decodeShard(record.payload)
            if (shard != null) ShardStore.add(context, shard, reason = reason, sourceRef = record.id, creditMoney = false, decrypted = shard.decrypted)
            shard != null
        }
        ItemKind.DAEMON -> {
            val daemon = ItemPayload.decodeDaemon(record.payload)
            if (daemon != null) DaemonStore.grant(context, daemon.id, LootCodec.Loot.DaemonLoot(daemon.name, daemon.sequence, daemon.tier, daemon.effect), sourceRef = record.id, reason = reason)
            daemon != null
        }
    }
}
