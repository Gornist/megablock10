package com.megablok10.app.shards

import android.content.Context
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.ShardEntity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Шарды, отсканированные этим устройством, поверх Room. */
object ShardStore {
    fun observeAll(context: Context): Flow<List<Mb10Qr.Shard>> =
        Mb10Database.get(context).shardDao().observeAll().map { entities ->
            entities.map { Mb10Qr.Shard(it.id, it.badge, it.decryptAction, it.title, it.meta, it.body, it.moneyAmount, it.decrypted) }
        }

    /**
     * Деньги внутри шарда (если есть) зачисляются тут же, в момент сохранения —
     * тем же событием, что и появление шарда в коллекции. decrypted стартует
     * как !decryptAction: шард без требования расшифровки сразу открыт,
     * шард с decryptAction = true — заблокирован до успешного мини-взлома.
     */
    suspend fun add(context: Context, shard: Mb10Qr.Shard) {
        Mb10Database.get(context).shardDao().upsert(
            ShardEntity(
                id = shard.id,
                badge = shard.badge,
                decryptAction = shard.decryptAction,
                title = shard.title,
                meta = shard.meta,
                body = shard.body,
                scannedAt = System.currentTimeMillis(),
                moneyAmount = shard.moneyAmount,
                decrypted = !shard.decryptAction
            )
        )
        TransactionStore.creditShardMoney(context, shard.id, shard.moneyAmount, shard.title)
    }

    suspend fun markDecrypted(context: Context, id: String) {
        Mb10Database.get(context).shardDao().markDecrypted(id)
    }
}
