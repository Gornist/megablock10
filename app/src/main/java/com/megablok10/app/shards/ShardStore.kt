package com.megablok10.app.shards

import android.content.Context
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.Tier
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.ShardEntity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.json.JSONObject

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
    /** reason/sourceRef — откуда взялся шард для мастерского коллектора (§2.2 ТЗ): напрямую сканом или через grant() из контейнера. */
    suspend fun add(context: Context, shard: Mb10Qr.Shard, reason: String = ChangeReason.SHARD_SCAN, sourceRef: String? = null) {
        val acquiredAt = System.currentTimeMillis()
        Mb10Database.get(context).shardDao().upsert(
            ShardEntity(
                id = shard.id,
                decryptAction = shard.decryptAction,
                tier = shard.tier,
                valueHint = shard.valueHint,
                title = shard.title,
                meta = shard.meta,
                body = shard.body,
                scannedAt = acquiredAt,
                moneyAmount = shard.moneyAmount,
                decrypted = !shard.decryptAction
            )
        )
        TransactionStore.creditShardMoney(context, shard.id, shard.moneyAmount, shard.title)

        val entry = JSONObject()
            .put("shardId", shard.id)
            .put("title", shard.title)
            .put("tier", shard.tier.toString())
            .put("decrypted", !shard.decryptAction)
            .put("acquiredAt", acquiredAt)
            .put("sourceRef", sourceRef)
        ChangeRecordStore.enqueue(context, ChangeField.SHARDS_ADD, null, entry.toString(), reason, sourceRef ?: shard.id)
    }

    /** Шард, извлечённый из слота лута контейнера (см. DaemonRewards) — id детерминирован от slotRef. */
    suspend fun grant(context: Context, id: String, tier: Tier, loot: LootCodec.Loot.ShardLoot, sourceRef: String) {
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
            ),
            reason = ChangeReason.BREACH_LOOT,
            sourceRef = sourceRef
        )
    }

    suspend fun markDecrypted(context: Context, id: String) {
        Mb10Database.get(context).shardDao().markDecrypted(id)
        ChangeRecordStore.enqueue(
            context, ChangeField.SHARDS_DECRYPT, null,
            JSONObject().put("shardId", id).toString(),
            ChangeReason.SHARD_DECRYPT, sourceRef = id,
        )
    }
}
