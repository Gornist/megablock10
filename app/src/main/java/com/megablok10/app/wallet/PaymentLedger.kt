package com.megablok10.app.wallet

import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Денежный журнал глазами сценариев перевода и экранов: подписать и списать, доставить, отменить, принять, выдать чек.
 * Реализация — [TransactionStore] (Room, баланс, записи для мастера); в тестах сценариев и ViewModel — фейк.
 * Подробности правил — в документации методов [TransactionStore].
 */
interface PaymentLedger {
    fun observeAll(): Flow<List<TransactionEntity>>

    fun observeBalance(): Flow<Long>

    /** Подписанная карточка перевода от [me] игроку [toPubKeyB64] (формат TX v2, адресат в подписи). */
    fun signedTransaction(me: Identity, toPubKeyB64: String, amount: Long, memo: String, id: String = UUID.randomUUID().toString()): Mb10Qr.Transaction

    /** Списать сумму сразу (PENDING). false — не хватает денег, сумма некорректна или такой перевод уже есть. */
    suspend fun recordOutgoingPending(tx: Mb10Qr.Transaction, toPubKeyB64: String): Boolean

    /** Доставить карточку по протоколу kit handover (DELIVERED до отправки, откат только при NOT_REACHED). */
    suspend fun deliverOutgoing(id: String, willSend: Boolean, send: suspend () -> SendOutcome)

    /** Отменить недоставленный перевод и вернуть деньги. false — уже доставлен/подтверждён или записи нет. */
    suspend fun cancelOutgoing(id: String): Boolean

    /** Зафиксировать перевод по чеку получателя. */
    suspend fun verifyAndConfirmReceipt(pendingTxId: String, receipt: Mb10Qr.Receipt): Boolean

    /** Чек получателя [me] по переводу [transactionId] — ответ отправителю. */
    fun buildReceipt(me: Identity, transactionId: String): Mb10Qr.Receipt

    /** Принять входящий перевод: проверить подпись и адресата, зачислить. false — отказ или уже принят. */
    suspend fun recordIncoming(myPublicKeyB64: String, tx: Mb10Qr.Transaction): Boolean
}
