package com.megablok10.app.chat

import com.megablok10.app.data.OutboxDao
import com.megablok10.app.data.OutboxEntity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.log.shortKey
import com.megablok10.kit.mesh.Outbox
import com.megablok10.kit.mesh.OutboxEntry
import com.megablok10.kit.mesh.OutboxQueue
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.LineSocketClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val TAG = "OutboxStore"

/**
 * Очередь исходящих сообщений чата с повторами — механика в kit [Outbox] (docs/network-spec.md, §7): сообщение попадает сюда,
 * если получателя не видно или отправка не удалась, и уходит, как только он снова виден в сети (MeshSession зовёт [flush] при
 * изменении списка пиров и по таймеру). Что можно ставить в очередь, решает [OutboxPolicy.isQueueable]. Хранилище — таблица
 * Room `outbox`.
 */
class OutboxStore(
    dao: OutboxDao,
    lines: LineSocketClient,
    private val peers: () -> List<PeerInfo>,
) {
    private val outbox = Outbox(queue = RoomOutboxQueue(dao), log = Mb10Log, tag = TAG) { peer, line ->
        withContext(Dispatchers.IO) { lines.sendLine(peer.host, peer.port, line, 2000) }
    }

    suspend fun enqueue(toPubKeyB64: String, wire: ChatWireMessage) {
        outbox.enqueue(toPubKeyB64, ChatProtocol.encode(wire))
        Mb10Log.event(TAG, "outbox.enqueue", "to" to shortKey(toPubKeyB64), "type" to wire.type.name)
    }

    suspend fun pending(): Int = outbox.pending()

    /** Пробует отправить всё, что пора. Возвращает, сколько сообщений ушло. Параллельные вызовы не пересекаются. */
    suspend fun flush(): Int = outbox.flush(peers().associateBy { it.pubKeyB64 })
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
