package com.megablok10.app.chat

import android.content.Context
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.OutboxDao
import com.megablok10.app.data.OutboxEntity
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.LineTransport
import com.megablok10.app.presence.PresenceService
import com.megablok10.kit.log.shortKey
import com.megablok10.kit.mesh.Outbox
import com.megablok10.kit.mesh.OutboxEntry
import com.megablok10.kit.mesh.OutboxQueue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val TAG = "OutboxStore"

/**
 * Очередь исходящих сообщений чата с повторами — механика в kit [Outbox] (docs/network-spec.md, §7): сообщение попадает сюда,
 * если получателя не видно или отправка не удалась, и уходит, как только он снова виден в сети (см. ChatStore: flush по появлению
 * пира и по таймеру). Что можно ставить в очередь, решает [OutboxPolicy.isQueueable]. Хранилище — таблица Room `outbox`.
 */
object OutboxStore {
    @Volatile private var outbox: Outbox? = null

    private fun outbox(context: Context): Outbox = outbox ?: synchronized(this) {
        outbox ?: Outbox(
            queue = RoomOutboxQueue(Mb10Database.get(context).outboxDao()),
            log = Mb10Log,
            tag = TAG,
        ) { peer, line -> withContext(Dispatchers.IO) { LineTransport.client.sendLine(peer.host, peer.port, line, 2000) } }
            .also { outbox = it }
    }

    suspend fun enqueue(context: Context, toPubKeyB64: String, wire: ChatWireMessage) {
        outbox(context).enqueue(toPubKeyB64, ChatProtocol.encode(wire))
        Mb10Log.event(TAG, "outbox.enqueue", "to" to shortKey(toPubKeyB64), "type" to wire.type.name)
    }

    suspend fun pending(context: Context): Int = outbox(context).pending()

    /** Пробует отправить всё, что пора. Возвращает, сколько сообщений ушло. Параллельные вызовы не пересекаются. */
    suspend fun flush(context: Context): Int =
        outbox(context).flush(PresenceService.peers.value.associateBy { it.pubKeyB64 })
}

/** Таблица Room `outbox` как хранилище kit-очереди. Колонки те же, что были (миграция не нужна): wireLine — строка протокола целиком. */
internal class RoomOutboxQueue(private val dao: OutboxDao) : OutboxQueue {
    override suspend fun insert(toPubKeyB64: String, line: String, createdAt: Long) {
        dao.insert(OutboxEntity(toPubKeyB64 = toPubKeyB64, wireLine = line, createdAt = createdAt))
    }

    override suspend fun due(now: Long): List<OutboxEntry> =
        dao.due(now).map { OutboxEntry(it.id, it.toPubKeyB64, it.wireLine, it.createdAt, it.attempts, it.nextAttemptAt) }

    override suspend fun delete(id: Long) = dao.delete(id)
    override suspend fun reschedule(id: Long, attempts: Int, nextAttemptAt: Long) = dao.reschedule(id, attempts, nextAttemptAt)
    override suspend fun deleteOlderThan(cutoff: Long): Int = dao.deleteOlderThan(cutoff)
    override suspend fun count(): Int = dao.count()
}
