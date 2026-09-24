package com.megablok10.app.breach

import kotlinx.coroutines.flow.Flow

/**
 * Коллекция демонов глазами Кибердеки: наблюдать и завести стартовый набор персонажу без демонов. Реализация — [DaemonStore]
 * (Room, записи для мастера); в тестах ViewModel — фейк.
 */
interface DaemonCollection {
    fun observeAll(): Flow<List<Daemon>>

    /** Стартовый Datamine V1 — только если коллекция ещё пуста (новый персонаж или сброс сессии). */
    suspend fun ensureSeeded()
}
