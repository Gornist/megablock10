package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface TransactionDao {
    @Query("SELECT * FROM transactions ORDER BY timestamp DESC")
    fun observeAll(): Flow<List<TransactionEntity>>

    /**
     * IGNORE, не REPLACE — id транзакции одноразовый. Повторное сканирование
     * того же QR не должно зачислять деньги дважды. Возвращает -1, если
     * запись с таким id уже была (дедупликация), иначе rowid новой записи.
     */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(transaction: TransactionEntity): Long

    /** Переводит исходящую запись в CONFIRMED — из PENDING или DELIVERED (чек мог прийти и по недоставленной, с точки зрения отправителя, карточке). Возвращает число изменённых строк (0 или 1). */
    @Query("UPDATE transactions SET status = 'CONFIRMED' WHERE id = :id AND status IN ('PENDING', 'DELIVERED')")
    suspend fun confirm(id: String): Int

    /** Блокирует отмену: карточка уходит (или ушла) получателю. Только из PENDING. */
    @Query("UPDATE transactions SET status = 'DELIVERED' WHERE id = :id AND status = 'PENDING'")
    suspend fun markDelivered(id: String): Int

    /** Отправка не удалась — карточка получателя не достигла, отмена снова допустима. Только из DELIVERED. */
    @Query("UPDATE transactions SET status = 'PENDING' WHERE id = :id AND status = 'DELIVERED'")
    suspend fun markUndelivered(id: String): Int

    /** Удаляет запись, только если она ещё PENDING — подтверждённую отменить нельзя. Возвращает число удалённых строк. */
    @Query("DELETE FROM transactions WHERE id = :id AND status = 'PENDING'")
    suspend fun cancelPending(id: String): Int

    /** Контрагент записи — чтобы принять чек только от того, кому платёж реально адресован. */
    @Query("SELECT counterpartyPubKeyB64 FROM transactions WHERE id = :id")
    suspend fun counterpartyOf(id: String): String?

    /** Сумма записи (для исходящей — отрицательная) — нужна до удаления при отмене, чтобы отправить ChangeRecord с корректной дельтой. */
    @Query("SELECT amount FROM transactions WHERE id = :id")
    suspend fun amountOf(id: String): Long?

    /** Разовый снимок баланса (не Flow) — нужен, чтобы посчитать oldValue/newValue для ChangeRecord в момент мутации, см. TransactionStore. */
    @Query("SELECT COALESCE(SUM(amount), 0) FROM transactions")
    suspend fun currentBalance(): Long
}
