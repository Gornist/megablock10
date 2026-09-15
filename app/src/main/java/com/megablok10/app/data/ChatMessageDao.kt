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
}
