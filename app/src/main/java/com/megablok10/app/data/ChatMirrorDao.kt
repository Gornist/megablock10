package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Запросы к переписке для зеркала на очки (headset.HeadsetMirror): только чтение, схема Room не затронута. Отдельным интерфейсом, а не в
 * [ChatMessageDao], который и так на пределе по числу функций.
 */
@Dao
interface ChatMirrorDao {
    /** Любое изменение таблицы сообщений (новое сообщение, смена статуса): значение само не важно, важен повод перечитать. */
    @Query("SELECT COUNT(*) * 1000003 + COALESCE(SUM(status), 0) + COALESCE(MAX(id), 0) FROM chat_messages")
    fun observeStamp(): Flow<Long>

    /** Ключи собеседников, с которыми есть личная переписка. */
    @Query(
        """
        SELECT DISTINCT CASE WHEN fromPubKeyB64 = :myPubKey THEN toPubKeyB64 ELSE fromPubKeyB64 END
        FROM chat_messages WHERE type = 'DM' AND (fromPubKeyB64 = :myPubKey OR toPubKeyB64 = :myPubKey)
        """
    )
    suspend fun directPeers(myPubKey: String): List<String>

    /** Последние [limit] сообщений личного диалога, старые первыми. */
    @Query(
        """
        SELECT * FROM (
            SELECT * FROM chat_messages
            WHERE type = 'DM' AND (
                (fromPubKeyB64 = :myPubKey AND toPubKeyB64 = :peerPubKey) OR
                (fromPubKeyB64 = :peerPubKey AND toPubKeyB64 = :myPubKey)
            )
            ORDER BY timestamp DESC, id DESC LIMIT :limit
        ) ORDER BY timestamp ASC, id ASC
        """
    )
    suspend fun recentDirect(myPubKey: String, peerPubKey: String, limit: Int): List<ChatMessageEntity>

    /** Последние [limit] сообщений фракционного чата, старые первыми. */
    @Query(
        """
        SELECT * FROM (
            SELECT * FROM chat_messages WHERE type = 'FACTION' AND faction = :faction ORDER BY timestamp DESC, id DESC LIMIT :limit
        ) ORDER BY timestamp ASC, id ASC
        """
    )
    suspend fun recentFaction(faction: String, limit: Int): List<ChatMessageEntity>
}
