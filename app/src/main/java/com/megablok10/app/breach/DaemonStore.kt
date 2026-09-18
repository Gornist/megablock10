package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.data.DaemonEntity
import com.megablok10.app.data.Mb10Database
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.json.JSONObject

/**
 * Демоны персонажа поверх Room — не фиксированный список, а коллекция,
 * которая пополняется в течение игры. При первом запуске содержит только
 * стартовый Datamine V1 (MockBreach.daemons); дальше пополняется извлечением
 * из контейнеров (effect = EXTRACT_DAEMON, см. DaemonRewards.grant) —
 * отдельных QR-демонов больше нет (ревизия v9). Демон, в отличие от лута
 * контейнера, многоразовый: попав в кибердеку, он доступен на любом
 * будущем взломе, а не тратится.
 */
object DaemonStore {
    fun observeAll(context: Context): Flow<List<Daemon>> =
        Mb10Database.get(context).daemonDao().observeAll().map { entities ->
            entities.map {
                Daemon(
                    id = it.id,
                    name = it.name,
                    sequence = it.sequence.split(","),
                    tier = Tier.fromLevel(it.tier),
                    effect = DaemonEffect.entries.find { e -> e.name == it.effect } ?: DaemonEffect.EXTRACT_SHARD
                )
            }
        }

    suspend fun ensureSeeded(context: Context) {
        val dao = Mb10Database.get(context).daemonDao()
        if (dao.count() == 0) {
            dao.insertAll(MockBreach.daemons.map {
                DaemonEntity(id = it.id, name = it.name, sequence = it.sequence.joinToString(","), tier = it.tier.level, effect = it.effect.name)
            })
        }
    }

    /** Демон, извлечённый из слота лута (см. DaemonRewards) — id детерминирован от slotRef, повторное извлечение того же слота не плодит дубликат в коллекции. */
    suspend fun grant(context: Context, id: String, loot: LootCodec.Loot.DaemonLoot, sourceRef: String) {
        Mb10Database.get(context).daemonDao().upsert(
            DaemonEntity(id = id, name = loot.name, sequence = loot.sequence.joinToString(","), tier = loot.tier.level, effect = loot.effect.name)
        )
        // weight — в игровой модели такого поля нет (только Compose Modifier.weight не в счёт);
        // берём длину сигнатуры сопоставления как ближайший осмысленный аналог для дашборда.
        val entry = JSONObject()
            .put("daemonId", id)
            .put("name", loot.name)
            .put("tier", loot.tier.level.toString())
            .put("weight", loot.sequence.size)
            .put("acquiredAt", System.currentTimeMillis())
            .put("sourceRef", sourceRef)
        ChangeRecordStore.enqueue(context, ChangeField.DAEMONS_ADD, null, entry.toString(), ChangeReason.BREACH_LOOT, sourceRef)
    }
}
