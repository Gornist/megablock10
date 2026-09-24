package com.megablok10.app.chat

import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.Identity
import kotlinx.coroutines.flow.Flow

/**
 * Переписка глазами инбокса: лента фракции, превью личных тредов, отправка в общий фракционный чат. Реализация —
 * [ChatStore] (Room, сеть, очередь исходящих); в тестах [com.megablok10.app.ui.screens.ChatViewModel] — фейк.
 */
interface ChatInbox {
    fun observeFaction(faction: String): Flow<List<ChatMessageEntity>>

    /** Последнее сообщение с каждым собеседником. */
    fun observeRecentDirectThreads(myPubKey: String): Flow<List<ChatMessageEntity>>

    suspend fun sendFaction(identity: Identity, body: String)
}
