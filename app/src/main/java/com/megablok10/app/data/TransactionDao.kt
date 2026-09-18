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

    /** Переводит исходящую запись в CONFIRMED — только пока она ещё PENDING. Возвращает число изменённых строк (0 или 1). */
    @Query("UPDATE transactions SET status = 'CONFIRMED' WHERE id = :id AND status = 'PENDING'")
    suspend fun confirm(id: String): Int

    /** Удаляет запись, только если она ещё PENDING — подтверждённую отменить нельзя. Возвращает число удалённых строк. */
    @Query("DELETE FROM transactions WHERE id = :id AND status = 'PENDING'")
    suspend fun cancelPending(id: String): Int

    /** Разовый снимок баланса (не Flow) — нужен, чтобы посчитать oldValue/newValue для ChangeRecord в момент мутации, см. TransactionStore. */
    @Query("SELECT COALESCE(SUM(amount), 0) FROM transactions")
    suspend fun currentBalance(): Long
}
