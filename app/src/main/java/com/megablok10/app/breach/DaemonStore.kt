package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.data.DaemonEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Демоны персонажа поверх Room — не фиксированный список, а коллекция,
 * которая пополняется в течение игры. При первом запуске пуста и заполняется
 * стартовым набором из MockBreach; дальше это единственный источник правды,
 * MockBreach.daemons после сева больше не используется на экране. Новые
 * демоны появляются через QR мастера (Мастерская → "Демон") — см. add().
 */
object DaemonStore {
    fun observeAll(context: Context): Flow<List<Daemon>> =
        Mb10Database.get(context).daemonDao().observeAll().map { entities ->
            entities.map {
                Daemon(it.id, it.name, it.sequence.split(","), it.reward, it.rewardMoney, it.rewardShardTitle, it.rewardShardMeta, it.rewardShardBody)
            }
        }

    suspend fun ensureSeeded(context: Context) {
        val dao = Mb10Database.get(context).daemonDao()
        if (dao.count() == 0) {
            dao.insertAll(MockBreach.daemons.map { DaemonEntity(it.id, it.name, it.sequence.joinToString(","), it.reward) })
        }
    }

    /** Демон-предмет, отсканированный из QR мастера — попадает в кибердеку этого устройства, доступен для выбора на любом взломе. */
    suspend fun add(context: Context, item: Mb10Qr.DaemonItem) {
        Mb10Database.get(context).daemonDao().upsert(
            DaemonEntity(
                id = item.id,
                name = item.name,
                sequence = item.sequence.joinToString(","),
                reward = item.reward,
                rewardMoney = item.rewardMoney,
                rewardShardTitle = item.rewardShardTitle,
                rewardShardMeta = item.rewardShardMeta,
                rewardShardBody = item.rewardShardBody
            )
        )
    }
}
