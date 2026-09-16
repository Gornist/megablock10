package com.megablok10.app.wallet

import android.content.Context
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Локальный денежный журнал устройства поверх Room. Баланс — не отдельное
 * поле, а сумма amount по всем записям (PENDING считаются наравне с
 * CONFIRMED — деньги уже не в руках игрока с момента генерации QR).
 */
object TransactionStore {
    fun observeAll(context: Context): Flow<List<TransactionEntity>> =
        Mb10Database.get(context).transactionDao().observeAll()

    fun observeBalance(context: Context): Flow<Long> =
        observeAll(context).map { list -> list.sumOf { it.amount } }

    /**
     * Плательщик списывает у себя сумму СРАЗУ при отправке — как отдать
     * наличные из рук в руки. Статус PENDING: пока получатель не подтвердил
     * чеком (сообщением), что деньги реально дошли, плательщик ещё может
     * отменить платёж и вернуть себе деньги (см. cancelOutgoing) — например,
     * если получатель так и не принял перевод. toPubKeyB64 известен сразу —
     * получатель выбирается из контактов перед отправкой, а не определяется
     * тем, кто отсканировал QR, как раньше.
     */
    suspend fun recordOutgoingPending(context: Context, tx: Mb10Qr.Transaction, toPubKeyB64: String) {
        Mb10Database.get(context).transactionDao().insertIfAbsent(
            TransactionEntity(
                id = tx.id,
                counterpartyPubKeyB64 = toPubKeyB64,
                amount = -tx.amount,
                memo = tx.memo,
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.PENDING
            )
        )
    }

    /** Отменяет ещё не подтверждённый платёж и возвращает деньги. false, если запись уже подтверждена или не найдена. */
    suspend fun cancelOutgoing(context: Context, id: String): Boolean =
        Mb10Database.get(context).transactionDao().cancelPending(id) > 0

    /**
     * Фиксирует платёж по чеку получателя — с этого момента отменить его
     * уже нельзя. Именно эта проверка и не даёт "нажать отменить и оставить
     * деньги себе" после того, как получатель их реально получил.
     */
    suspend fun verifyAndConfirmReceipt(context: Context, pendingTxId: String, receipt: Mb10Qr.Receipt): Boolean {
        if (receipt.id != pendingTxId) return false
        val payload = Mb10QrCodec.receiptSignaturePayload(receipt.id, receipt.receiverPubKeyB64)
        if (!IdentityManager.verify(receipt.receiverPubKeyB64, payload, receipt.signatureB64)) return false
        return Mb10Database.get(context).transactionDao().confirm(receipt.id) > 0
    }

    /** Чек, который получатель показывает в ответ отправителю — доказательство, что деньги реально получены. */
    fun buildReceipt(context: Context, identity: Identity, transactionId: String): Mb10Qr.Receipt {
        val payload = Mb10QrCodec.receiptSignaturePayload(transactionId, identity.publicKeyB64)
        val signature = IdentityManager.sign(context, payload)
        return Mb10Qr.Receipt(id = transactionId, receiverPubKeyB64 = identity.publicKeyB64, signatureB64 = signature)
    }

    /**
     * Получатель проверяет подпись плательщика тем же публичным ключом, что
     * зашит в его Contact-QR, и зачисляет сумму себе — сразу как CONFIRMED,
     * получателю отменять нечего. Возвращает false, если подпись не сошлась,
     * сумма некорректна, это своя же транзакция или она уже была зачислена
     * раньше (защита от повторного скана одного QR).
     */
    suspend fun recordIncoming(context: Context, myPublicKeyB64: String, tx: Mb10Qr.Transaction): Boolean {
        if (tx.amount <= 0) return false
        if (tx.fromPubKeyB64 == myPublicKeyB64) return false
        val payload = Mb10QrCodec.transactionSignaturePayload(tx.id, tx.fromPubKeyB64, tx.amount, tx.memo)
        if (!IdentityManager.verify(tx.fromPubKeyB64, payload, tx.signatureB64)) return false

        val rowId = Mb10Database.get(context).transactionDao().insertIfAbsent(
            TransactionEntity(
                id = tx.id,
                counterpartyPubKeyB64 = tx.fromPubKeyB64,
                amount = tx.amount,
                memo = tx.memo,
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
        return rowId != -1L
    }

    /**
     * Деньги внутри шарда — находка, а не перевод от игрока: подписи тут
     * нет и проверять нечего, доверие идёт от самого факта, что шард
     * физически найден и отсканирован. Идемпотентность — через тот же
     * insertIfAbsent, что и у обычных транзакций: id записи привязан к id
     * шарда, поэтому повторный скан того же шарда (тот же QR, другая
     * копия, случайный повтор) не зачисляет деньги дважды.
     */
    suspend fun creditShardMoney(context: Context, shardId: String, amount: Long, shardTitle: String) {
        if (amount <= 0) return
        Mb10Database.get(context).transactionDao().insertIfAbsent(
            TransactionEntity(
                id = "shard:$shardId",
                counterpartyPubKeyB64 = "",
                amount = amount,
                memo = "Шард: $shardTitle",
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
    }

    /**
     * Деньги за совпадение денежного демона на взломе — тот же принцип, что
     * у денег внутри шарда: находка, а не перевод, идемпотентность через id
     * записи, привязанный к id демона (см. DaemonRewards.apply).
     */
    suspend fun creditDaemonReward(context: Context, daemonId: String, amount: Long, daemonName: String) {
        if (amount <= 0) return
        Mb10Database.get(context).transactionDao().insertIfAbsent(
            TransactionEntity(
                id = "daemon:$daemonId",
                counterpartyPubKeyB64 = "",
                amount = amount,
                memo = "Демон: $daemonName",
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
    }
}
