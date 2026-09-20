package com.megablok10.app.chat

import android.content.Context
import android.util.Log
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.OutboxEntity
import com.megablok10.app.net.LineSocketClient
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
    }

    suspend fun pending(context: Context): Int = Mb10Database.get(context).outboxDao().count()

    /** Пробует отправить всё, что пора. Возвращает, сколько сообщений ушло. Параллельные вызовы не пересекаются. */
    suspend fun flush(context: Context, now: Long = System.currentTimeMillis()): Int = flushLock.withLock {
        val dao = Mb10Database.get(context).outboxDao()
        dao.deleteOlderThan(now - OutboxPolicy.MAX_AGE_MS)
        val peers = PresenceService.peers.value.associateBy { it.pubKeyB64 }
        var sent = 0
        for (entry in dao.due(now)) {
            val peer = peers[entry.toPubKeyB64] ?: continue   // не виден — не считаем попыткой, ждём его появления
            val ok = withContext(Dispatchers.IO) { LineSocketClient.sendLine(peer.host, peer.port, entry.wireLine, 2000) }
            if (ok) {
                dao.delete(entry.id); sent++
            } else {
                val attempts = entry.attempts + 1
                dao.reschedule(entry.id, attempts, now + OutboxPolicy.nextDelayMs(attempts))
            }
        }
        if (sent > 0) Log.i(TAG, "досланы из очереди: $sent")
        sent
    }
}
