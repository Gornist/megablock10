package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.ReceiptConfirmer
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.ItemTransferEntity
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.identity.Identity
import com.megablok10.app.items.AcceptItem
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.wallet.AcceptPayment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Содержимое личного треда из базы: переписка и журналы переводов и передач — по ним карточки в ленте показывают статус. */
data class ThreadFeed(
    val messages: List<ChatMessageEntity> = emptyList(),
    val transactions: List<TransactionEntity> = emptyList(),
    val itemTransfers: List<ItemTransferEntity> = emptyList(),
)

data class DirectThreadState(val feed: ThreadFeed = ThreadFeed(), val contacts: ContactsView = ContactsView())

/**
 * Личный тред с игроком [peerKey]: лента, отправка, «Принять» на карточках перевода и предмета (сценарии AcceptPayment/AcceptItem —
 * зачислить и ответить чеком). Чеки из истории треда перепроверяются при показе ([ReceiptConfirmer]): обычно чек подтверждает
 * передачу уже при приёме с сети, это запасной путь для чеков, пришедших до этого механизма.
 */
class DirectThreadViewModel(
    val peerKey: String,
    private val identity: StateFlow<Identity?>,
    feed: Flow<ThreadFeed>,
    directory: ContactDirectory,
    private val messenger: DirectMessenger,
    private val acceptPayment: AcceptPayment,
    private val acceptItem: AcceptItem,
    private val receipts: ReceiptConfirmer,
    private val work: CoroutineScope,
) : ViewModel() {
    private var receiptsChecked = 0

    val state: StateFlow<DirectThreadState> = combine(feed.onEach { confirmNewReceipts(it.messages) }, directory.view, ::DirectThreadState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), DirectThreadState())

    fun send(body: String) {
        val me = identity.value ?: return
        work.launch { messenger.sendDirect(me, peerKey, messenger.onlinePeer(peerKey), body) }
    }

    fun accept(tx: Mb10Qr.Transaction) {
        val me = identity.value ?: return
        work.launch { acceptPayment(me, tx) }
    }

    fun accept(card: Mb10Qr.ItemTransfer) {
        val me = identity.value ?: return
        work.launch { acceptItem(me, card) }
    }

    /** Только новый хвост ленты: тред может разрастись на сотни сообщений, полный пересчёт на каждое новое был бы лишней работой. */
    private suspend fun confirmNewReceipts(messages: List<ChatMessageEntity>) {
        val me = identity.value?.publicKeyB64 ?: return
        messages.drop(receiptsChecked).forEach { msg ->
            if (msg.fromPubKeyB64 != me) (Mb10QrCodec.decode(msg.body) as? Mb10Qr.Receipt)?.let { receipts.confirm(it) }
        }
        receiptsChecked = messages.size
    }
}
