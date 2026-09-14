package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.data.DaemonEntity
import com.megablok10.app.data.Mb10Database
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Демоны персонажа поверх Room — не фиксированный список, а коллекция,
 * которая пополняется в течение игры. При первом запуске пуста и заполняется
 * стартовым набором из MockBreach; дальше это единственный источник правды,
 * MockBreach.daemons после сева больше не используется на экране.
 */
object DaemonStore {
    fun observeAll(context: Context): Flow<List<Daemon>> =
        Mb10Database.get(context).daemonDao().observeAll().map { entities ->
            entities.map { Daemon(it.id, it.name, it.sequence.split(","), it.reward) }
        }

    suspend fun ensureSeeded(context: Context) {
        val dao = Mb10Database.get(context).daemonDao()
        if (dao.count() == 0) {
            dao.insertAll(MockBreach.daemons.map { DaemonEntity(it.id, it.name, it.sequence.joinToString(","), it.reward) })
        }
    }
}
