package com.megablok10.app.shards

import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.Tier
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.ShardDao
import com.megablok10.app.data.ShardEntity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.wallet.TransactionStore
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.Transactor
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.json.JSONObject

/** Шарды, отсканированные этим устройством или извлечённые из контейнера, поверх Room. */
class ShardStore(
    private val dao: ShardDao,
    private val wallet: TransactionStore,
    private val changes: ChangeRecorder,
    private val tx: Transactor,
) : ShardCollection {
    override fun observeAll(): Flow<List<Mb10Qr.Shard>> =
        dao.observeAll().map { entities -> entities.map { it.toShard() } }

    /** Шард из коллекции (для передачи другому игроку); null — такого у игрока нет. */
    suspend fun get(id: String): Mb10Qr.Shard? = dao.get(id)?.toShard()

    /**
     * Деньги внутри шарда (если есть) зачисляются тут же, в момент сохранения —
     * тем же событием, что и появление шарда в коллекции. decrypted стартует
     * как !decryptAction: шард без требования расшифровки сразу открыт,
     * шард с decryptAction = true — заблокирован до успешного мини-взлома.
     *
     * reason/sourceRef — откуда взялся шард для мастерского коллектора (§2.2 ТЗ): напрямую сканом или через grant() из контейнера.
     */
    override suspend fun add(
        shard: Mb10Qr.Shard,
        reason: String,
        sourceRef: String?,
        creditMoney: Boolean,
        decrypted: Boolean
    ): Unit = tx.inTransaction {
        // Шард, деньги из него и записи о них для мастера — один коммит: падение посередине не оставит одно без другого.
        val acquiredAt = System.currentTimeMillis()
        dao.upsert(
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
                decrypted = decrypted
            )
        )
        // Деньги внутри шарда зачисляются один раз — тому, кто его нашёл; при передаче другому игроку повторно их не начисляем.
        if (creditMoney) wallet.creditShardMoney(shard.id, shard.moneyAmount, shard.title)

        val entry = JSONObject()
            .put("shardId", shard.id)
            .put("title", shard.title)
            .put("tier", shard.tier.toString())
            .put("decrypted", decrypted)
            .put("acquiredAt", acquiredAt)
            .put("sourceRef", sourceRef)
        changes.record(ChangeField.SHARDS_ADD, null, entry.toString(), reason, sourceRef ?: shard.id)
    }

    /** Шард, извлечённый из слота лута контейнера (см. DaemonRewards) — id детерминирован от slotRef. */
    suspend fun grant(id: String, tier: Tier, loot: LootCodec.Loot.ShardLoot, sourceRef: String) {
        add(
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

    /** Убирает шард из коллекции (передача другому игроку) и сообщает об этом дашборду. */
    suspend fun remove(id: String, reason: String, sourceRef: String): Unit = tx.inTransaction {
        dao.delete(id)
        changes.record(ChangeField.SHARDS_REMOVE, null, JSONObject().put("shardId", id).toString(), reason, sourceRef)
    }

    override suspend fun markDecrypted(id: String): Unit = tx.inTransaction {
        dao.markDecrypted(id)
        changes.record(
            ChangeField.SHARDS_DECRYPT, null,
            JSONObject().put("shardId", id).toString(),
            ChangeReason.SHARD_DECRYPT, sourceRef = id,
        )
    }

    private fun ShardEntity.toShard() = Mb10Qr.Shard(id, decryptAction, tier, valueHint, title, meta, body, moneyAmount, decrypted)
}
