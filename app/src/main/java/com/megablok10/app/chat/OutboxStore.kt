package com.megablok10.app.chat

import android.content.Context
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.OutboxDao
import com.megablok10.app.data.OutboxEntity
import com.megablok10.app.net.LineSocketClient
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

private const val TAG = "OutboxStore"

/**
 * Очередь исходящих сообщений с повторами. Сообщение попадает сюда, если получателя не видно или отправка не удалась, и уходит,
 * как только он снова виден в сети (см. ChatStore: flush по появлению пира и по таймеру). Повтор с нарастающей паузой
 * ([OutboxPolicy.nextDelayMs]); что ушло — удаляется; что старше [OutboxPolicy.MAX_AGE_MS] — тоже.
 */
object OutboxStore {
    private val flushLock = Mutex()

    suspend fun enqueue(context: Context, toPubKeyB64: String, wire: ChatWireMessage) {
        Mb10Database.get(context).outboxDao().insert(
            OutboxEntity(toPubKeyB64 = toPubKeyB64, wireLine = ChatProtocol.encode(wire), createdAt = System.currentTimeMillis())
        )
        Mb10Log.event(TAG, "outbox.enqueue", "to" to Mb10Log.short(toPubKeyB64), "type" to wire.type.name)
    }

    suspend fun pending(context: Context): Int = Mb10Database.get(context).outboxDao().count()

    /** Пробует отправить всё, что пора. Возвращает, сколько сообщений ушло. Параллельные вызовы не пересекаются. */
    suspend fun flush(context: Context, now: Long = System.currentTimeMillis()): Int = flushLock.withLock {
        val sent = flushOutbox(
            Mb10Database.get(context).outboxDao(),
            PresenceService.peers.value.associateBy { it.pubKeyB64 },
            now
        ) { peer, line -> withContext(Dispatchers.IO) { LineSocketClient.sendLine(peer.host, peer.port, line, 2000) } }
        if (sent > 0) Mb10Log.event(TAG, "outbox.flushed", "sent" to sent, "left" to Mb10Database.get(context).outboxDao().count())
        sent
    }
}

/** Ядро отправки очереди без Android: выбрасывает просроченное, шлёт то, что пора и чей адресат виден, пересчитывает паузу неудачным. */
internal suspend fun flushOutbox(
    dao: OutboxDao,
    peers: Map<String, PeerInfo>,
    now: Long,
    send: suspend (PeerInfo, String) -> Boolean
): Int {
    dao.deleteOlderThan(now - OutboxPolicy.MAX_AGE_MS)
    var sent = 0
    for (entry in dao.due(now)) {
        val peer = peers[entry.toPubKeyB64] ?: continue   // не виден — не считаем попыткой, ждём его появления
        if (send(peer, entry.wireLine)) {
            dao.delete(entry.id); sent++
            Mb10Log.event(TAG, "outbox.sent", "id" to entry.id, "to" to Mb10Log.short(entry.toPubKeyB64), "attempts" to entry.attempts, "ageMs" to (now - entry.createdAt))
        } else {
            val attempts = entry.attempts + 1
            Mb10Log.warnEvent(TAG, "outbox.retry", "id" to entry.id, "to" to Mb10Log.short(entry.toPubKeyB64), "attempts" to attempts, "nextInMs" to OutboxPolicy.nextDelayMs(attempts))
            dao.reschedule(entry.id, attempts, now + OutboxPolicy.nextDelayMs(attempts))
        }
    }
    return sent
}
