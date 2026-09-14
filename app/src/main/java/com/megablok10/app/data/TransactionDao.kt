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
}
