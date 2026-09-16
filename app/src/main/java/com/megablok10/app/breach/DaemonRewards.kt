package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.wallet.TransactionStore

/**
 * Применяет эффект совпавших демонов после резолва попытки — деньги и/или
 * шард, если они у демона заданы (см. Daemon.rewardMoney/rewardShard* в
 * BreachEngine.kt). У стартовых демонов эти поля пустые, вызов для них —
 * no-op. Награда демона — одноразовая на всю игру (не за конкретный
 * взлом): id записи привязан к id демона, повторное совпадение того же
 * демона на другом взломе уже ничего не зачисляет (TransactionStore.
 * insertIfAbsent / ShardDao REPLACE тем же id).
 */
object DaemonRewards {
    suspend fun apply(context: Context, result: BreachResult) {
        if (result.outcome == BreachOutcome.FAIL) return
        result.allDaemons.filter { it.id in result.matchedIds }.forEach { daemon ->
            if (daemon.rewardMoney > 0) {
                TransactionStore.creditDaemonReward(context, daemon.id, daemon.rewardMoney, daemon.name)
            }
            val shardTitle = daemon.rewardShardTitle
            if (!shardTitle.isNullOrBlank()) {
                ShardStore.add(
                    context,
                    Mb10Qr.Shard(
                        id = "daemon-reward:${daemon.id}",
                        badge = "Public",
                        decryptAction = false,
                        title = shardTitle,
                        meta = daemon.rewardShardMeta.orEmpty(),
                        body = daemon.rewardShardBody.orEmpty(),
                        moneyAmount = 0,
                        decrypted = true
                    )
                )
            }
        }
    }
}
