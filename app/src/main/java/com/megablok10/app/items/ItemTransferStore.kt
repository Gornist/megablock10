package com.megablok10.app.items

import androidx.room.withTransaction
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.MockBreach
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.ItemTransferDao
import com.megablok10.app.data.ItemTransferEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.shards.ShardStore
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.handover.Handover
import com.megablok10.kit.handover.HandoverRules
import com.megablok10.kit.handover.OutgoingJournal
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.Flow
import java.util.UUID

private const val TAG = "Items"

/**
 * Передача шардов и демонов между игроками — тот же протокол, что у денег (kit [Handover], см. TransactionStore):
 * предмет уходит из коллекции отправителя сразу (PENDING), карточка доставляется получателю
 * (DELIVERED — с этого момента отмена запрещена), получатель нажимает «Принять» и шлёт чек (CONFIRMED).
 * Предметы не копируются, а именно передаются: у получателя они появляются только при принятии,
 * у отправителя пропадают при отправке, отмена недоставленной передачи возвращает предмет.
 */
class ItemTransferStore(
    private val db: Mb10Database,
    private val identity: IdentityStore,
    private val shards: ShardStore,
    private val daemons: DaemonStore,
    private val chat: ChatStore,
    private val peers: () -> List<PeerInfo>,
) {
    private val dao = db.itemTransferDao()
    private val handover = Handover(ItemTransferJournal(dao), Mb10Log, tag = TAG, eventPrefix = "item")

    fun observeAll(): Flow<List<ItemTransferEntity>> = dao.observeAll()

    // Проверка «предмет ещё у меня» и его списание — одной транзакцией: иначе двойной тап по «Передать» создавал бы две передачи одного предмета.
    suspend fun sendShard(me: Identity, shardId: String, toPubKeyB64: String): Mb10Qr.ItemTransfer? =
        db.withTransaction {
            val shard = shards.get(shardId) ?: return@withTransaction null
            sendOut(me, ItemKind.SHARD, ItemPayload.encodeShard(shard), toPubKeyB64) { id ->
                shards.remove(shardId, ChangeReason.ITEM_TRANSFER_OUT, sourceRef = id)
            }
        }

    suspend fun sendDaemon(me: Identity, daemon: Daemon, toPubKeyB64: String): Mb10Qr.ItemTransfer? {
        if (!isTransferable(daemon)) return null
        return db.withTransaction {
            if (daemons.get(daemon.id) == null) return@withTransaction null
            sendOut(me, ItemKind.DAEMON, ItemPayload.encodeDaemon(daemon), toPubKeyB64) { id ->
                daemons.remove(daemon.id, ChangeReason.ITEM_TRANSFER_OUT, sourceRef = id)
            }
        }
    }

    private suspend fun sendOut(
        me: Identity, kind: ItemKind, payload: String, toPubKeyB64: String, removeItem: suspend (transferId: String) -> Unit
    ): Mb10Qr.ItemTransfer? {
        if (toPubKeyB64 == me.publicKeyB64) return null
        val id = "item-${UUID.randomUUID()}"
        val signature = identity.sign(Mb10QrCodec.itemTransferSignaturePayload(id, me.publicKeyB64, toPubKeyB64, kind, payload))
        val inserted = dao.insertIfAbsent(
            ItemTransferEntity(id, toPubKeyB64, kind.name, payload, System.currentTimeMillis(), TransactionStatus.PENDING, outgoing = true)
        )
        if (inserted == -1L) return null
        removeItem(id)
        Mb10Log.event(TAG, "item.out_created", "id" to id, "kind" to kind.name, "to" to Mb10Log.short(toPubKeyB64), "payloadChars" to payload.length)
        return Mb10Qr.ItemTransfer(id, me.publicKeyB64, toPubKeyB64, kind, payload, signature)
    }

    /** Как TransactionStore.deliverOutgoing: DELIVERED ставится ДО отправки, откат — только если соединиться не удалось (NOT_REACHED). */
    suspend fun deliverOutgoing(id: String, willSend: Boolean, send: suspend () -> SendOutcome) =
        handover.deliver(id, willSend, send)

    /** Отмена недоставленной передачи: предмет возвращается в коллекцию. false — карточка уже доставлена/подтверждена или записи нет. */
    suspend fun cancelOutgoing(id: String): Boolean {
        val record = dao.get(id) ?: run { Mb10Log.warnEvent(TAG, "item.cancel", "id" to id, "result" to "нет такой записи"); return false }
        if (!record.outgoing || dao.cancelPending(id) == 0) { Mb10Log.warnEvent(TAG, "item.cancel", "id" to id, "result" to "отказ: уже доставлена/подтверждена"); return false }
        restore(record, ChangeReason.ITEM_TRANSFER_CANCELLED)
        Mb10Log.event(TAG, "item.cancel", "id" to id, "result" to "отменена, предмет возвращён", "kind" to record.kind)
        return true
    }

    /** Чек получателя фиксирует передачу — те же проверки, что у денег: чек подписал именно адресат этой передачи. */
    suspend fun verifyAndConfirmReceipt(id: String, receipt: Mb10Qr.Receipt): Boolean =
        handover.confirmByReceipt(id, receipt.id, receipt.receiverPubKeyB64, receipt.signatureB64)

    /** Получатель проверяет подпись отправителя и кладёт предмет в коллекцию. false — подпись не сошлась, своя же карточка или уже принято. */
    suspend fun acceptIncoming(myPubKeyB64: String, card: Mb10Qr.ItemTransfer): Boolean {
        fun reject(why: String): Boolean { Mb10Log.warnEvent(TAG, "item.in_rejected", "id" to card.id, "from" to Mb10Log.short(card.fromPubKeyB64), "kind" to card.kind.name, "why" to why); return false }
        // Адресат в подписи: чужую копию карточки принять нельзя (иначе один предмет можно получить дважды).
        val signed = Mb10QrCodec.itemTransferSignaturePayload(card.id, card.fromPubKeyB64, card.toPubKeyB64, card.kind, card.payload)
        HandoverRules.rejectIncoming(card.fromPubKeyB64, card.toPubKeyB64, myPubKeyB64, signed, card.signatureB64, Ecdsa::verify)?.let { return reject(it) }

        val record = ItemTransferEntity(card.id, card.fromPubKeyB64, card.kind.name, card.payload, System.currentTimeMillis(), TransactionStatus.CONFIRMED, outgoing = false)
        // Запись-«принято» ставится первой: если предмет не разобрался, откатываем её, иначе карточка «сгорит» без выдачи.
        if (dao.insertIfAbsent(record) == -1L) return reject("уже принята раньше")
        if (!restore(record, ChangeReason.ITEM_TRANSFER_IN)) {
            dao.delete(card.id)
            return reject("содержимое не разобралось")
        }
        Mb10Log.event(TAG, "item.in_accepted", "id" to card.id, "from" to Mb10Log.short(card.fromPubKeyB64), "kind" to card.kind.name)
        return true
    }

    /** Отправляет карточку получателю как личное сообщение: сохраняет её в тред, а если он в сети — доставляет и помечает DELIVERED. */
    suspend fun deliver(me: Identity, card: Mb10Qr.ItemTransfer, toPubKeyB64: String) {
        val peer = peers().find { it.pubKeyB64 == toPubKeyB64 }
        deliverOutgoing(card.id, willSend = peer != null) {
            chat.sendDirectOutcome(me, toPubKeyB64, peer, Mb10QrCodec.encodeItemTransfer(card))
        }
    }

    /** Чек получателя [me] по передаче [id] — тот же формат, что у денег (kit HandoverRules.receiptSignaturePayload). */
    fun buildReceipt(me: Identity, id: String): Mb10Qr.Receipt =
        Mb10Qr.Receipt(id = id, receiverPubKeyB64 = me.publicKeyB64, signatureB64 = identity.sign(HandoverRules.receiptSignaturePayload(id, me.publicKeyB64)))

    /** Кладёт предмет из журнала в коллекцию (принятие у получателя или возврат при отмене у отправителя). */
    private suspend fun restore(record: ItemTransferEntity, reason: String): Boolean = when (ItemKind.valueOf(record.kind)) {
        ItemKind.SHARD -> {
            val shard = ItemPayload.decodeShard(record.payload)
            if (shard != null) shards.add(shard, reason = reason, sourceRef = record.id, creditMoney = false, decrypted = shard.decrypted)
            shard != null
        }
        ItemKind.DAEMON -> {
            val daemon = ItemPayload.decodeDaemon(record.payload)
            if (daemon != null) daemons.grant(daemon.id, LootCodec.Loot.DaemonLoot(daemon.name, daemon.sequence, daemon.tier, daemon.effect), sourceRef = record.id, reason = reason)
            daemon != null
        }
    }

    companion object {
        /** Стартовый демон есть у каждого персонажа и пересеивается при пустой коллекции — передавать его нельзя, иначе он размножался бы. */
        fun isTransferable(daemon: Daemon): Boolean = MockBreach.daemons.none { it.id == daemon.id }
    }
}

/**
 * Таблица `item_transfers` как журнал исходящих карточек kit-протокола передачи. Входящие записи (outgoing = false) — отметки
 * «уже принято»: чек по ним не принимается, переходы статусов их не трогают (условие outgoing = 1 в запросах ItemTransferDao).
 */
private class ItemTransferJournal(private val dao: ItemTransferDao) : OutgoingJournal {
    override suspend fun markDelivered(id: String) = dao.markDelivered(id)
    override suspend fun markUndelivered(id: String) = dao.markUndelivered(id)
    override suspend fun confirm(id: String) = dao.confirm(id)
    override suspend fun recipientOf(id: String) = dao.get(id)?.takeIf { it.outgoing }?.counterpartyPubKeyB64
}
