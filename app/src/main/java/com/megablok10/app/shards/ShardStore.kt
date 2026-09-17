package com.megablok10.app.shards

import android.content.Context
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.Tier
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.ShardEntity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Шарды, отсканированные этим устройством или извлечённые из контейнера, поверх Room. */
object ShardStore {
    fun observeAll(context: Context): Flow<List<Mb10Qr.Shard>> =
        Mb10Database.get(context).shardDao().observeAll().map { entities ->
            entities.map { Mb10Qr.Shard(it.id, it.decryptAction, it.tier, it.valueHint, it.title, it.meta, it.body, it.moneyAmount, it.decrypted) }
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
                decryptAction = shard.decryptAction,
                tier = shard.tier,
                valueHint = shard.valueHint,
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

    /** Шард, извлечённый из слота лута контейнера (см. DaemonRewards) — id детерминирован от slotRef. */
    suspend fun grant(context: Context, id: String, tier: Tier, loot: LootCodec.Loot.ShardLoot) {
        add(
            context,
            Mb10Qr.Shard(
                id = id,
                decryptAction = loot.decryptAction,
                tier = tier.level,
                valueHint = loot.valueHint,
                title = loot.title,
                meta = loot.meta,
                body = loot.body,
                moneyAmount = loot.moneyAmount
            )
        )
    }

    suspend fun markDecrypted(context: Context, id: String) {
        Mb10Database.get(context).shardDao().markDecrypted(id)
    }
}
