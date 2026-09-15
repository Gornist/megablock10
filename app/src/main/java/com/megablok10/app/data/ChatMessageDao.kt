package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ChatMessageDao {
    @Insert
    suspend fun insert(message: ChatMessageEntity): Long

    @Query("SELECT * FROM chat_messages WHERE type = 'FACTION' AND faction = :faction ORDER BY timestamp ASC")
    fun observeFaction(faction: String): Flow<List<ChatMessageEntity>>

    @Query(
        """
        SELECT * FROM chat_messages
        WHERE type = 'DM' AND (
            (fromPubKeyB64 = :myPubKey AND toPubKeyB64 = :peerPubKey) OR
            (fromPubKeyB64 = :peerPubKey AND toPubKeyB64 = :myPubKey)
        )
        ORDER BY timestamp ASC
        """
    )
    fun observeDirect(myPubKey: String, peerPubKey: String): Flow<List<ChatMessageEntity>>

    /**
     * Один — последний — ряд на каждого собеседника, для инбокса со списком
     * диалогов (как в обычных мессенджерах), не полная история. GROUP BY по
     * "второй стороне" (не важно, я отправитель или получатель), а бесхозные
     * (не агрегатные) колонки в SELECT рядом с MAX() — намеренно: это
     * задокументированное поведение SQLite (bare-column-takes-value-from-
     * max-row), а не случайность — иначе пришлось бы городить самосоединение.
     */
    @Query(
        """
        SELECT *, MAX(timestamp) FROM chat_messages
        WHERE type = 'DM' AND (fromPubKeyB64 = :myPubKey OR toPubKeyB64 = :myPubKey)
        GROUP BY CASE WHEN fromPubKeyB64 = :myPubKey THEN toPubKeyB64 ELSE fromPubKeyB64 END
        ORDER BY timestamp DESC
        """
    )
    fun observeRecentDirectThreads(myPubKey: String): Flow<List<ChatMessageEntity>>
}
