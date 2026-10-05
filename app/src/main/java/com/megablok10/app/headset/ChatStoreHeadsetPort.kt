package com.megablok10.app.headset

import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.ChatMirrorDao
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Переписка для зеркала на очки поверх Room и [ChatStore]. Отправка идёт тем же путём, что и из интерфейса
 * (`ChatStore.sendDirect`/`sendFaction`): сообщение сохраняется, уходит адресату или встаёт в очередь исходящих.
 */
class ChatStoreHeadsetPort(
    private val dao: ChatMirrorDao,
    private val chat: ChatStore,
    private val contacts: ContactStore,
) : HeadsetChatPort {
    override fun changes(me: Identity): Flow<Unit> = dao.observeStamp().map { }

    override suspend fun directPeers(me: String): List<String> = dao.directPeers(me)

    override suspend fun recentDirect(me: String, peerPubKey: String, limit: Int): List<ChatMessageEntity> = dao.recentDirect(me, peerPubKey, limit)

    override suspend fun recentFaction(faction: String, limit: Int): List<ChatMessageEntity> = dao.recentFaction(faction, limit)

    override suspend fun peerCallsign(pubKey: String): String? =
        contacts.observeAll().first().firstOrNull { it.publicKeyB64 == pubKey }?.callsign ?: chat.onlinePeer(pubKey)?.callsign

    override suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, text: String): Boolean =
        chat.sendDirect(identity, peerPubKeyB64, chat.onlinePeer(peerPubKeyB64), text)

    override suspend fun sendFaction(identity: Identity, text: String) = chat.sendFaction(identity, text)

    override fun contacts(): Flow<List<HeadsetContact>> = contacts.observeAll().map { list -> list.map { HeadsetContact(it.publicKeyB64, it.callsign) } }
}
