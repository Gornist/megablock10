package com.megablok10.app.shards

import android.content.Context
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.ShardEntity
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Шарды, отсканированные этим устройством, поверх Room. */
object ShardStore {
    fun observeAll(context: Context): Flow<List<Mb10Qr.Shard>> =
        Mb10Database.get(context).shardDao().observeAll().map { entities ->
            entities.map { Mb10Qr.Shard(it.id, it.badge, it.decryptAction, it.title, it.meta, it.body) }
        }

    suspend fun add(context: Context, shard: Mb10Qr.Shard) {
        Mb10Database.get(context).shardDao().upsert(
            ShardEntity(
                id = shard.id,
                badge = shard.badge,
                decryptAction = shard.decryptAction,
                title = shard.title,
                meta = shard.meta,
                body = shard.body,
                scannedAt = System.currentTimeMillis()
            )
        )
    }
}
