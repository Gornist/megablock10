package com.megablok10.app.breach

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.DaemonDao
import com.megablok10.app.data.DaemonEntity
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.Transactor
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
class DaemonStore(
    private val dao: DaemonDao,
    private val changes: ChangeRecorder,
    private val tx: Transactor,
) : DaemonCollection {
    override fun observeAll(): Flow<List<Daemon>> = dao.observeAll().map { entities -> entities.map { it.toDaemon() } }

    /** Демон из коллекции (для передачи другому игроку); null — такого у игрока нет. */
    suspend fun get(id: String): Daemon? = dao.get(id)?.toDaemon()

    override suspend fun ensureSeeded() {
        if (dao.count() == 0) {
            dao.insertAll(MockBreach.daemons.map {
                DaemonEntity(id = it.id, name = it.name, sequence = it.sequence.joinToString(","), tier = it.tier.level, effect = it.effect.name)
            })
        }
    }

    /** Демон, извлечённый из слота лута (см. DaemonRewards) — id детерминирован от slotRef, повторное извлечение того же слота не плодит дубликат в коллекции. */
    suspend fun grant(id: String, loot: LootCodec.Loot.DaemonLoot, sourceRef: String, reason: String = ChangeReason.BREACH_LOOT): Unit = tx.inTransaction {
        dao.upsert(
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
        changes.record(ChangeField.DAEMONS_ADD, null, entry.toString(), reason, sourceRef)
    }

    /** Убирает демона из коллекции (передача другому игроку) и сообщает об этом дашборду. */
    suspend fun remove(id: String, reason: String, sourceRef: String): Unit = tx.inTransaction {
        dao.delete(id)
        changes.record(ChangeField.DAEMONS_REMOVE, null, JSONObject().put("daemonId", id).toString(), reason, sourceRef)
    }

    private fun DaemonEntity.toDaemon() = Daemon(
        id = id,
        name = name,
        sequence = sequence.split(","),
        tier = Tier.fromLevel(tier),
        effect = DaemonEffect.entries.find { e -> e.name == effect } ?: DaemonEffect.EXTRACT_SHARD
    )
}
