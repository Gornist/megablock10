package com.megablok10.app.items

import com.megablok10.app.breach.Daemon
import com.megablok10.app.data.ItemTransferEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.Flow

/**
 * Журнал передач предметов глазами сценариев и экранов — тот же протокол, что у денег ([com.megablok10.app.wallet.PaymentLedger]).
 * Реализация — [ItemTransferStore]; в тестах сценариев и ViewModel — фейк.
 */
interface ItemLedger {
    fun observeAll(): Flow<List<ItemTransferEntity>>

    /** Забрать шард из коллекции и подписать карточку передачи. null — шарда нет, адресат — сам игрок или сбой записи. */
    suspend fun sendShard(me: Identity, shardId: String, toPubKeyB64: String): Mb10Qr.ItemTransfer?

    /** То же для демона; стартовые демоны не передаются (null). */
    suspend fun sendDaemon(me: Identity, daemon: Daemon, toPubKeyB64: String): Mb10Qr.ItemTransfer?

    /** Доставить карточку по протоколу kit handover (DELIVERED до отправки, откат только при NOT_REACHED). */
    suspend fun deliverOutgoing(id: String, willSend: Boolean, send: suspend () -> SendOutcome)

    /** Отменить недоставленную передачу — предмет возвращается. false — уже доставлена/подтверждена или записи нет. */
    suspend fun cancelOutgoing(id: String): Boolean

    /** Зафиксировать передачу по чеку получателя. */
    suspend fun verifyAndConfirmReceipt(id: String, receipt: Mb10Qr.Receipt): Boolean

    /** Принять входящую карточку: проверить подпись и адресата, положить предмет в коллекцию. false — отказ или уже принята. */
    suspend fun acceptIncoming(myPubKeyB64: String, card: Mb10Qr.ItemTransfer): Boolean

    /** Чек получателя [me] по передаче [id] — ответ отправителю. */
    fun buildReceipt(me: Identity, id: String): Mb10Qr.Receipt
}
