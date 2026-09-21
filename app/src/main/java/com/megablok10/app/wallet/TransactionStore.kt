package com.megablok10.app.wallet

import android.content.Context
import androidx.room.withTransaction
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.TransactionDao
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.net.SendOutcome
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
        val db = Mb10Database.get(context)
        val dao = db.transactionDao()
        if (tx.amount <= 0) return false
        // Проверка баланса и вставка — одной транзакцией: иначе два быстрых перевода (двойной тап «Отправить») оба видели бы прежний
        // баланс, проходили проверку и уводили отправителя в минус, а получателям зачислялись бы полные суммы — деньги из воздуха.
        val rowId = db.withTransaction {
            if (tx.amount > dao.currentBalance()) return@withTransaction -1L
            dao.insertIfAbsent(
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
        if (rowId != -1L) emitBalanceChange(context, dao, -tx.amount, ChangeReason.TRANSFER_OUT, sourceRef = tx.id)
        return rowId != -1L
    }

    /**
     * Отправляет платёжную карточку получателю так, чтобы отмену нельзя было
     * провести одновременно с доставкой: статус DELIVERED ставится ДО отправки
     * (иначе "отменить" во время полёта карточки оставило бы деньги у обоих) и
     * откатывается в PENDING, только если отправка точно не удалась. willSend =
     * false — получатель офлайн, карточка не уходит вовсе (send() лишь сохранит
     * сообщение в локальный тред), запись остаётся PENDING и отменяема.
     * Откат делается ТОЛЬКО при [SendOutcome.NOT_REACHED] (соединиться не удалось — карточка точно не ушла). Если ошибка случилась
     * уже после соединения ([SendOutcome.UNKNOWN]), карточка могла дойти: платёж остаётся DELIVERED и отменить его нельзя —
     * лучше заморозить сумму до чека или вмешательства мастера, чем оставить её у обоих.
     */
    suspend fun deliverOutgoing(context: Context, id: String, willSend: Boolean, send: suspend () -> SendOutcome) {
        val dao = Mb10Database.get(context).transactionDao()
        if (!willSend) {
            send()
            return
        }
        dao.markDelivered(id)
        if (send() == SendOutcome.NOT_REACHED) dao.markUndelivered(id)
    }

    /**
     * Отменяет платёж, карточка которого получателю НЕ доставлена (статус
     * PENDING — он был офлайн или отправка не удалась). Доставленный (DELIVERED)
     * и подтверждённый платёж отменить нельзя: получатель мог уже нажать
     * "Принять", и отмена оставила бы сумму у обоих (см. deliverOutgoing).
     * false, если запись не PENDING или не найдена.
     *
     * Отмена уходит на дашборд компенсирующим ChangeRecord с причиной
     * TRANSFER_CANCELLED и тем же txId в sourceRef: сервер по нему помечает
     * перевод "отменён отправителем" вместо висящего одностороннего.
     */
    suspend fun cancelOutgoing(context: Context, id: String): Boolean {
        val dao = Mb10Database.get(context).transactionDao()
        val amount = dao.amountOf(id) ?: return false
        if (dao.cancelPending(id) == 0) return false
        // amount исходящей записи отрицательный — деньги возвращаются, дельта баланса положительная.
        emitBalanceChange(context, dao, -amount, ChangeReason.TRANSFER_CANCELLED, sourceRef = id)
        return true
    }

    /**
     * Фиксирует платёж по чеку получателя — с этого момента отменить его
     * уже нельзя. Именно эта проверка и не даёт "нажать отменить и оставить
     * деньги себе" после того, как получатель их реально получил.
     */
    suspend fun verifyAndConfirmReceipt(context: Context, pendingTxId: String, receipt: Mb10Qr.Receipt): Boolean {
        if (receipt.id != pendingTxId) return false
        // Чек должен подписать именно адресат платежа — иначе любой контакт мог бы "подтвердить" чужой платёж (и тем самым заблокировать его отмену).
        if (Mb10Database.get(context).transactionDao().counterpartyOf(receipt.id) != receipt.receiverPubKeyB64) return false
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
        // Карточка адресована не мне — копия, пересланная сообщником или перехваченная в сети: принять её значило бы создать деньги из воздуха.
        if (tx.toPubKeyB64 != myPublicKeyB64) return false
        val payload = Mb10QrCodec.transactionSignaturePayload(tx.id, tx.fromPubKeyB64, tx.toPubKeyB64, tx.amount, tx.memo)
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
     * Стартовый баланс персонажа из QR мастера (ProvisionStore): баланс становится РОВНО [balance], а не «плюс столько». В базе могли остаться
     * записи прежней сессии (сброс сессии стирает только ключи), поэтому сумма записи — разность. Идемпотентно по id выдачи. Уходит на дашборд
     * записью баланса с причиной CHARACTER_CREATED — тем же способом, каким телефон сообщает о любом изменении.
     */
    suspend fun setStartingBalance(context: Context, provisionId: String, balance: Long) {
        val dao = Mb10Database.get(context).transactionDao()
        val delta = balance - dao.currentBalance()
        if (delta == 0L) return
        val rowId = dao.insertIfAbsent(
            TransactionEntity(
                id = "prov:$provisionId",
                counterpartyPubKeyB64 = "",
                amount = delta,
                memo = "Стартовый баланс",
                timestamp = System.currentTimeMillis(),
                status = TransactionStatus.CONFIRMED
            )
        )
        if (rowId != -1L) emitBalanceChange(context, dao, delta, ChangeReason.CHARACTER_CREATED, sourceRef = provisionId)
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
