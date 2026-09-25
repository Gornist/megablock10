package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Журнал передач шардов и демонов между игроками — тот же протокол, что у денег (см. TransactionStatus):
 * у отправителя запись OUT проходит PENDING → DELIVERED → CONFIRMED (предмет уходит из коллекции сразу,
 * отмена возможна только пока карточка не доставлена), у получателя запись IN появляется в момент
 * принятия и сразу CONFIRMED. Запись IN ещё и защита от повторного «Принять» на старой карточке:
 * без неё предмет, уже переданный дальше, можно было бы вернуть себе и размножить.
 */
@Entity(tableName = "item_transfers")
data class ItemTransferEntity(
    @PrimaryKey val id: String,
    val counterpartyPubKeyB64: String,
    val kind: String,
    /** Сам предмет в том виде, в каком он едет по проводу (см. ItemTransferStore) — нужен, чтобы вернуть его при отмене. */
    val payload: String,
    val timestamp: Long,
    val status: String,
    val outgoing: Boolean
)

@Dao
interface ItemTransferDao {
    /** Исходящие передачи, доставленные адресату, но без его чека, — созданные раньше [before] (см. chat.CardResender). */
    @Query("SELECT * FROM item_transfers WHERE status = 'DELIVERED' AND outgoing = 1 AND timestamp < :before")
    suspend fun deliveredUnconfirmed(before: Long): List<ItemTransferEntity>

    @Query("SELECT * FROM item_transfers ORDER BY timestamp DESC")
    fun observeAll(): Flow<List<ItemTransferEntity>>

    @Query("SELECT * FROM item_transfers WHERE id = :id")
    suspend fun get(id: String): ItemTransferEntity?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(entity: ItemTransferEntity): Long

    @Query("DELETE FROM item_transfers WHERE id = :id")
    suspend fun delete(id: String)

    @Query("UPDATE item_transfers SET status = 'DELIVERED' WHERE id = :id AND status = 'PENDING' AND outgoing = 1")
    suspend fun markDelivered(id: String): Int

    @Query("UPDATE item_transfers SET status = 'PENDING' WHERE id = :id AND status = 'DELIVERED' AND outgoing = 1")
    suspend fun markUndelivered(id: String): Int

    @Query("UPDATE item_transfers SET status = 'CONFIRMED' WHERE id = :id AND outgoing = 1 AND status IN ('PENDING','DELIVERED')")
    suspend fun confirm(id: String): Int

    @Query("DELETE FROM item_transfers WHERE id = :id AND outgoing = 1 AND status = 'PENDING'")
    suspend fun cancelPending(id: String): Int
}
