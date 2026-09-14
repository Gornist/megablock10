package com.megablok10.app.wallet

import android.content.Context
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Локальный денежный журнал устройства поверх Room. Баланс — не отдельное
 * поле, а сумма amount по всем записям: то же самое "сколько раз кто-то
 * подтвердил передачу", что и во всём остальном протоколе (контакты, шарды).
 */
object TransactionStore {
    fun observeAll(context: Context): Flow<List<TransactionEntity>> =
        Mb10Database.get(context).transactionDao().observeAll()

    fun observeBalance(context: Context): Flow<Long> =
        observeAll(context).map { list -> list.sumOf { it.amount } }

    /**
     * Плательщик списывает у себя сумму СРАЗУ при генерации QR — как отдать
     * наличные из рук в руки, без подтверждения от получателя. Кто именно
     * отсканирует, в этот момент ещё не известно, поэтому counterparty пуст.
     */
    suspend fun recordOutgoing(context: Context, tx: Mb10Qr.Transaction) {
        Mb10Database.get(context).transactionDao().insertIfAbsent(
            TransactionEntity(
                id = tx.id,
                counterpartyPubKeyB64 = "",
                amount = -tx.amount,
                memo = tx.memo,
                timestamp = System.currentTimeMillis()
            )
        )
    }

    /**
     * Получатель проверяет подпись плательщика тем же публичным ключом, что
     * зашит в его Contact-QR, и зачисляет сумму себе. Возвращает false, если
     * подпись не сошлась, сумма некорректна, это своя же транзакция или она
     * уже была зачислена раньше (защита от повторного скана одного QR).
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
                timestamp = System.currentTimeMillis()
            )
        )
        return rowId != -1L
    }
}
