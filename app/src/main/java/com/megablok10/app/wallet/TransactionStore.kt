package com.megablok10.app.wallet

import android.content.Context
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.TransactionDao
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
    suspend fun recordOutgoingPending(context: Context, tx: Mb10Qr.Transaction, toPubKeyB64: String): Boolean {
        val dao = Mb10Database.get(context).transactionDao()
        // Без этой проверки перевод больше баланса уводил отправителя в минус, а получателю
        // зачислялась полная сумма — то есть деньги можно было печатать себе через сообщника.
        if (tx.amount <= 0 || tx.amount > dao.currentBalance()) return false
        val rowId = dao.insertIfAbsent(
            TransactionEntity(
                id = tx.id,
                counterpartyPubKeyB64 = toPubKeyB64,
                amount = -tx.amount,
                memo = tx.memo,
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.PENDING
            )
        )
        if (rowId != -1L) emitBalanceChange(context, dao, -tx.amount, ChangeReason.TRANSFER_OUT, sourceRef = tx.id)
        return rowId != -1L
    }

    /**
     * Отменяет ещё не подтверждённый платёж и возвращает деньги. false, если
     * запись уже подтверждена или не найдена.
     *
     * ИЗВЕСТНЫЙ ПРОБЕЛ: локальный баланс на устройстве откатывается верно
     * (запись просто удаляется из transactions), но компенсирующий
     * ChangeRecord сюда не шлётся — в наборе причин ТЗ (§2.2) нет отдельного
     * "перевод отменён", а слать второй TRANSFER_OUT с тем же txId сбило бы
     * сведение по txId на дашборде. Итог: если платёж отменили ДО того, как
     * получатель подтвердил чек, баланс в дашборде на копейку разойдётся с
     * реальным — на масштабе одного акта LARP решили этим пренебречь, а не
     * городить отдельную причину ради редкого кейса.
     */
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

        val dao = Mb10Database.get(context).transactionDao()
        val rowId = dao.insertIfAbsent(
            TransactionEntity(
                id = tx.id,
                counterpartyPubKeyB64 = tx.fromPubKeyB64,
                amount = tx.amount,
                memo = tx.memo,
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
        if (rowId != -1L) {
            emitBalanceChange(context, dao, tx.amount, ChangeReason.TRANSFER_IN, sourceRef = tx.id, actor = tx.fromPubKeyB64)
        }
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
        val dao = Mb10Database.get(context).transactionDao()
        val rowId = dao.insertIfAbsent(
            TransactionEntity(
                id = "shard:$shardId",
                counterpartyPubKeyB64 = "",
                amount = amount,
                memo = "Шард: $shardTitle",
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
        if (rowId != -1L) emitBalanceChange(context, dao, amount, ChangeReason.SHARD_SCAN, sourceRef = shardId)
    }

    /**
     * Эдди за успешный (SUCCESS/PARTIAL) взлом контейнера — ревизия v9 §2:
     * сумма зависит от тира контейнера, не от конкретного демона (денежных
     * демонов больше нет). attemptId уникален на попытку (не на контейнер и
     * не на демона) — это не разовая награда, а честный доход за каждый
     * успешно пройденный (и не заблокированный кулдауном) взлом; тот же
     * insertIfAbsent защищает только от повторного зачисления ОДНОЙ и той
     * же попытки, если вызов почему-то продублируется.
     */
    suspend fun creditContainerEddies(context: Context, attemptId: String, amount: Long, containerName: String) {
        if (amount <= 0) return
        val dao = Mb10Database.get(context).transactionDao()
        val rowId = dao.insertIfAbsent(
            TransactionEntity(
                id = "breach:$attemptId",
                counterpartyPubKeyB64 = "",
                amount = amount,
                memo = "Взлом: $containerName",
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
        if (rowId != -1L) emitBalanceChange(context, dao, amount, ChangeReason.BREACH_EDDIES, sourceRef = attemptId)
    }

    /**
     * Применяет правку баланса от мастера с дашборда (§6.3 ТЗ) — newValue
     * абсолютный, не дельта. В отличие от emitBalanceChange НЕ шлёт
     * ChangeRecord обратно на коллектор (эта правка сама следствие уже
     * существующей записи в его истории — эхо было бы дублем). id записи —
     * id самого MASTER_OVERRIDE с сервера, поэтому insertIfAbsent защищает
     * от повторного применения при повторной доставке.
     */
    suspend fun applyBalanceOverride(context: Context, changeId: String, newBalance: Long, memo: String) {
        val dao = Mb10Database.get(context).transactionDao()
        val currentBalance = dao.currentBalance()
        dao.insertIfAbsent(
            TransactionEntity(
                id = "override:$changeId",
                counterpartyPubKeyB64 = "",
                amount = newBalance - currentBalance,
                memo = "Правка мастера: $memo",
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED,
            ),
        )
    }

    /**
     * newValue — баланс ПОСЛЕ применения delta (снимок читаем уже после
     * insert), oldValue выводим вычитанием — дешевле, чем читать баланс
     * дважды, и корректно, поскольку мутация и чтение идут последовательно
     * в одной suspend-цепочке одного вызова (гонок с самим собой нет).
     */
    private suspend fun emitBalanceChange(
        context: Context,
        dao: TransactionDao,
        delta: Long,
        reason: String,
        sourceRef: String,
        actor: String? = null,
    ) {
        val newBalance = dao.currentBalance()
        val oldBalance = newBalance - delta
        ChangeRecordStore.enqueue(context, ChangeField.BALANCE, oldBalance.toString(), newBalance.toString(), reason, sourceRef, actor = actor)
    }
}
