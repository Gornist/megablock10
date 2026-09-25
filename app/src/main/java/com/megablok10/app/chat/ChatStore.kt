package com.megablok10.app.chat

import com.megablok10.app.data.ChatMessageDao
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.LineSocketClient
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

private const val TAG = "ChatStore"

/**
 * Переписка: сохранение в Room, чтение тредов и отправка по сети напрямую адресату (kit [LineSocketClient], одна строка на
 * соединение). Что не ушло — в очередь исходящих ([outbox]), кроме денег и предметов (см. OutboxPolicy). Приём с провода и
 * жизненный цикл сети — в MeshSession; этот класс только хранит и отправляет.
 */
class ChatStore(
    private val dao: ChatMessageDao,
    private val outbox: OutboxStore,
    private val lines: LineSocketClient,
    private val peers: () -> List<PeerInfo>,
) : DirectMessenger, ChatInbox {
    override fun onlinePeer(pubKeyB64: String): PeerInfo? = peers().find { it.pubKeyB64 == pubKeyB64 }

    override fun observeFaction(faction: String): Flow<List<ChatMessageEntity>> = dao.observeFaction(faction)

    fun observeDirect(myPubKey: String, peerPubKey: String): Flow<List<ChatMessageEntity>> = dao.observeDirect(myPubKey, peerPubKey)

    /** Последнее сообщение с каждым собеседником — для инбокса. */
    override fun observeRecentDirectThreads(myPubKey: String): Flow<List<ChatMessageEntity>> = dao.observeRecentDirectThreads(myPubKey)

    /** Сохраняет свою копию сразу и рассылает всем сейчас видимым игрокам своей фракции; кому не ушло — в очередь исходящих. */
    override suspend fun sendFaction(identity: Identity, body: String) {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.FACTION, identity.publicKeyB64, identity.callsign, identity.faction, "", timestamp, body)
        persist(wire)
        val recipients = peers().filter { it.faction == identity.faction }
        Mb10Log.event(TAG, "chat.send_faction", "recipients" to recipients.size, "chars" to body.length)
        val line = ChatProtocol.encode(wire)
        withContext(Dispatchers.IO) {
            recipients.forEach { peer -> if (!lines.sendLine(peer.host, peer.port, line)) outbox.enqueue(peer.pubKeyB64, wire) }
        }
    }

    /**
     * peerPubKeyB64 — личность адресата (известна всегда, из контактов, вне
     * зависимости от того, онлайн он сейчас или нет) — именно она идёт в
     * запись треда, иначе observeDirect потом не найдёт своё же сообщение по
     * фильтру "от меня к нему". peer — живой адрес для реальной отправки
     * (null, если сейчас не в сети): без него есть кому, но некуда стучаться,
     * сообщение всё равно останется в треде локально.
     */
    override suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, peer: PeerInfo?, body: String): Boolean =
        sendDirectOutcome(identity, peerPubKeyB64, peer, body) == SendOutcome.DELIVERED

    /** Как [sendDirect], но с различением «точно не ушло» и «могло уйти» — нужно деньгам и предметам (kit handover). */
    override suspend fun sendDirectOutcome(identity: Identity, peerPubKeyB64: String, peer: PeerInfo?, body: String): SendOutcome {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.DM, identity.publicKeyB64, identity.callsign, identity.faction, peerPubKeyB64, timestamp, body)
        persist(wire)
        val outcome = if (peer == null) SendOutcome.NOT_REACHED else withContext(Dispatchers.IO) { lines.sendLineOutcome(peer.host, peer.port, ChatProtocol.encode(wire)) }
        val queued = outcome != SendOutcome.DELIVERED && OutboxPolicy.isQueueable(body)
        Mb10Log.event(TAG, "chat.send_direct", "to" to Mb10Log.short(peerPubKeyB64), "peerVisible" to (peer != null), "outcome" to outcome.name, "queued" to queued, "chars" to body.length)
        // Не ушло (адресата не видно или обрыв на роуминге) — в очередь: уйдёт само, когда он появится. Деньги/предметы не queue-им, см. OutboxPolicy.
        if (queued) outbox.enqueue(peerPubKeyB64, wire)
        return outcome
    }

    /** Своё сообщение с карточкой [transferId] адресату [to] — то самое, что ушло (то же время и текст: у получателя повтор — дубль). */
    suspend fun outgoingCard(me: String, to: String, transferId: String): ChatWireMessage? =
        dao.outgoingCard(me, to, transferId)?.let {
            ChatWireMessage(ChatMessageType.valueOf(it.type), it.fromPubKeyB64, it.fromCallsign, it.faction, it.toPubKeyB64, it.timestamp, it.body)
        }

    /** Отправить уже сохранённое сообщение ещё раз, без новой копии в своём треде. */
    suspend fun resend(peer: PeerInfo, message: ChatWireMessage): Boolean =
        withContext(Dispatchers.IO) { lines.sendLine(peer.host, peer.port, ChatProtocol.encode(message)) }

    /** Дослать очередь исходящих тем, кто сейчас виден (сессия зовёт при изменении списка пиров и по таймеру). */
    suspend fun flushOutbox(): Int = outbox.flush()

    /** Сохраняет входящее с провода, если такого ещё нет (тот же отправитель, время, тип и текст). false — это повтор (досылка из чужой очереди). */
    suspend fun receive(message: ChatWireMessage): Boolean {
        if (dao.countSame(message.fromPubKeyB64, message.timestamp, message.type.name, message.body) > 0) return false
        persist(message)
        return true
    }

    private suspend fun persist(message: ChatWireMessage) {
        dao.insert(
            ChatMessageEntity(
                type = message.type.name,
                fromPubKeyB64 = message.fromPubKeyB64,
                fromCallsign = message.fromCallsign,
                faction = message.fromFaction,
                toPubKeyB64 = message.toPubKeyB64,
                body = message.body,
                timestamp = message.timestamp
            )
        )
    }
}
