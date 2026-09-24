package com.megablok10.app.shards

import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.flow.Flow

/**
 * Коллекция шардов глазами Кибердеки: наблюдать, добавить со скана, отметить расшифрованным. Реализация — [ShardStore]
 * (Room, деньги внутри шарда, записи для мастера); в тестах ViewModel и [com.megablok10.app.cyberdeck.ScanObject] — фейк.
 */
interface ShardCollection {
    fun observeAll(): Flow<List<Mb10Qr.Shard>>

    /** Шард со скана — деньги внутри (если есть) зачисляются тем же вызовом, см. [ShardStore.add]. */
    suspend fun add(
        shard: Mb10Qr.Shard,
        reason: String = ChangeReason.SHARD_SCAN,
        sourceRef: String? = null,
        creditMoney: Boolean = true,
        decrypted: Boolean = !shard.decryptAction
    )

    suspend fun markDecrypted(id: String)
}
