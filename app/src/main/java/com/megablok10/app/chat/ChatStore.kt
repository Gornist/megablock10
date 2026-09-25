package com.megablok10.app.chat

import com.megablok10.app.data.ChatMessageDao
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

private const val TAG = "ChatStore"

/**
 * Переписка: сохранение в Room, чтение тредов и отправка по сети напрямую адресату (kit [PeerDirectory]: адрес и перебор адресов
 * игрока — там, одна строка на соединение). Что не ушло — в очередь исходящих ([outbox]), кроме денег и предметов (см. OutboxPolicy). Приём с провода и
 * жизненный цикл сети — в MeshSession; этот класс только хранит и отправляет.
 */
class ChatStore(
    private val dao: ChatMessageDao,
    private val outbox: OutboxStore,
    private val peers: PeerDirectory,
) : DirectMessenger, ChatInbox {
    override fun onlinePeer(pubKeyB64: String): OnlinePlayer? = peers.player(pubKeyB64)

    override fun observeFaction(faction: String): Flow<List<ChatMessageEntity>> = dao.observeFaction(faction)

    fun observeDirect(myPubKey: String, peerPubKey: String): Flow<List<ChatMessageEntity>> = dao.observeDirect(myPubKey, peerPubKey)

    /** Последнее сообщение с каждым собеседником — для инбокса. */
    override fun observeRecentDirectThreads(myPubKey: String): Flow<List<ChatMessageEntity>> = dao.observeRecentDirectThreads(myPubKey)

    /** Сохраняет свою копию сразу и рассылает всем сейчас видимым игрокам своей фракции; кому не ушло — в очередь исходящих. */
    override suspend fun sendFaction(identity: Identity, body: String) {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.FACTION, identity.publicKeyB64, identity.callsign, identity.faction, "", timestamp, body)
        persist(wire)
        // По одному разу на игрока (у него бывает несколько адресов — их перебирает PeerDirectory).
        val recipients = peers.online.value.filter { it.faction == identity.faction }.map { it.pubKeyB64 }
        Mb10Log.event(TAG, "chat.send_faction", "recipients" to recipients.size, "chars" to body.length)
        val line = ChatProtocol.encode(wire)
        withContext(Dispatchers.IO) {
            recipients.forEach { key ->
                if (peers.send(key, line) != SendOutcome.DELIVERED) outbox.enqueue(key, wire)
            }
        }
    }

    /**
     * peerPubKeyB64 — личность адресата (известна всегда, из контактов, вне
     * зависимости от того, онлайн он сейчас или нет) — именно она идёт в
     * запись треда, иначе observeDirect потом не найдёт своё же сообщение по
     * фильтру "от меня к нему". peer — живой адрес для реальной отправки
     * (null, если сейчас не в сети): без него есть кому, но некуда стучаться,
     * сообщение всё равно останется в треде локально. Какой из адресов игрока живой — решает PeerDirectory.
     */
    override suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, peer: OnlinePlayer?, body: String): Boolean =
        sendDirectOutcome(identity, peerPubKeyB64, peer, body) == SendOutcome.DELIVERED

    /** Как [sendDirect], но с различением «точно не ушло» и «могло уйти» — нужно деньгам и предметам (kit handover). */
    override suspend fun sendDirectOutcome(identity: Identity, peerPubKeyB64: String, peer: OnlinePlayer?, body: String): SendOutcome {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.DM, identity.publicKeyB64, identity.callsign, identity.faction, peerPubKeyB64, timestamp, body)
        val rowId = persist(wire)
        // peer == null — адресата нет в сети (или вызывающий нарочно отправляет «вне сети»): не стучимся никуда. Иначе — по всем его
        // адресам (PeerDirectory): запись NSD после перезапуска его приложения может ещё хранить порт прошлого процесса.
        val line = ChatProtocol.encode(wire)
        val outcome = if (peer == null) SendOutcome.NOT_REACHED else withContext(Dispatchers.IO) { peers.send(peerPubKeyB64, line) }
        val queued = outcome != SendOutcome.DELIVERED && OutboxPolicy.isQueueable(body)
        Mb10Log.event(TAG, "chat.send_direct", "to" to Mb10Log.short(peerPubKeyB64), "peerVisible" to (peer != null), "outcome" to outcome.name, "queued" to queued, "chars" to body.length)
        // Не ушло (адресата не видно или обрыв на роуминге) — в очередь: уйдёт само, когда он появится. Деньги/предметы не queue-им, см. OutboxPolicy.
        if (queued) outbox.enqueue(peerPubKeyB64, wire)
        dao.raiseStatus(rowId, statusOf(outcome))
        return outcome
    }

    /** Строка чата ушла из очереди или при переотправке и адресат подтвердил её (D2) — «доставлено» у своей копии. */
    suspend fun markDelivered(line: String) {
        val wire = ChatProtocol.decode(line) ?: return
        dao.raiseStatusOf(wire.fromPubKeyB64, wire.timestamp, wire.type.name, wire.body, MessageStatus.DELIVERED)
    }

    /** Своё сообщение с карточкой [transferId] адресату [to] — то самое, что ушло (то же время и текст: у получателя повтор — дубль). */
    suspend fun outgoingCard(me: String, to: String, transferId: String): ChatWireMessage? =
        dao.outgoingCard(me, to, transferId)?.let {
            ChatWireMessage(ChatMessageType.valueOf(it.type), it.fromPubKeyB64, it.fromCallsign, it.faction, it.toPubKeyB64, it.timestamp, it.body)
        }

    /** Отправить уже сохранённое сообщение ещё раз, без новой копии в своём треде. */
    suspend fun resend(toPubKeyB64: String, message: ChatWireMessage): Boolean {
        val line = ChatProtocol.encode(message)
        val delivered = withContext(Dispatchers.IO) { peers.send(toPubKeyB64, line) } == SendOutcome.DELIVERED
        if (delivered) markDelivered(line)
        return delivered
    }

    /** Дослать очередь исходящих тем, кто сейчас виден (сессия зовёт при изменении списка пиров и по таймеру). */
    suspend fun flushOutbox(): Int = outbox.flush()

    /** Сохраняет входящее с провода, если такого ещё нет (тот же отправитель, время, тип и текст). false — это повтор (досылка из чужой очереди). */
    suspend fun receive(message: ChatWireMessage): Boolean {
        if (dao.countSame(message.fromPubKeyB64, message.timestamp, message.type.name, message.body) > 0) return false
        persist(message)
        return true
    }

    private suspend fun persist(message: ChatWireMessage): Long =
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

/** Исход отправки → статус своей копии (MessageStatus). */
internal fun statusOf(outcome: SendOutcome): Int = when (outcome) {
    SendOutcome.DELIVERED -> MessageStatus.DELIVERED
    SendOutcome.UNKNOWN -> MessageStatus.SENT
    SendOutcome.NOT_REACHED -> MessageStatus.PENDING
}
