package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.chat.ChatInbox
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.identity.Identity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ChatInboxState(
    /** Лента фракции целиком: последняя — в превью инбокса, все — в треде фракции. */
    val factionMessages: List<ChatMessageEntity> = emptyList(),
    /** Последнее сообщение каждого личного диалога — строки инбокса. */
    val recentThreads: List<ChatMessageEntity> = emptyList(),
    val contacts: ContactsView = ContactsView(),
)

/**
 * Чат: инбокс, тред фракции и выбор собеседника для нового диалога. Лента фракции следует за текущей фракцией (мастер может её
 * сменить), личные треды — за ключом персонажа. Отдельный личный тред — [DirectThreadViewModel].
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChatViewModel(
    private val identity: StateFlow<Identity?>,
    private val chat: ChatInbox,
    directory: ContactDirectory,
    private val work: CoroutineScope,
) : ViewModel() {
    private val faction = identity.map { it?.faction }.distinctUntilChanged()
        .flatMapLatest { faction -> faction?.let(chat::observeFaction) ?: flowOf(emptyList()) }
    private val threads = identity.distinctKey()
        .flatMapLatest { key -> key?.let(chat::observeRecentDirectThreads) ?: flowOf(emptyList()) }

    val state: StateFlow<ChatInboxState> = combine(faction, threads, directory.view, ::ChatInboxState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), ChatInboxState())

    fun sendFaction(body: String) {
        val me = identity.value ?: return
        work.launch { chat.sendFaction(me, body) }
    }
}

/** Ключ персонажа без повторов: позывной и фракция меняются, а ключ — только при сбросе сессии. */
internal fun StateFlow<Identity?>.distinctKey(): Flow<String?> = map { it?.publicKeyB64 }.distinctUntilChanged()
