package com.megablok10.app.identity

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.ConsumedTokenDao
import com.megablok10.app.data.ConsumedTokenEntity
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.Transactor

/**
 * Применяет Mb10Qr.RamUpgrade к Identity.ramCapacity этого устройства ровно
 * один раз на токен — если карточку с QR сфотографируют и просканируют с
 * трёх разных телефонов, применится на каждом по разу (RAM хранится локально
 * на устройстве, не у сервера), но повторный скан ТОГО ЖЕ токена ТЕМ ЖЕ
 * устройством второй раз не сработает.
 */
class RamUpgradeStore(
    private val tokens: ConsumedTokenDao,
    private val identity: IdentityStore,
    private val changes: ChangeRecorder,
    private val tx: Transactor,
) {
    /**
     * null — токен уже был применён на этом устройстве раньше; иначе — новая ёмкость буфера.
     *
     * Токен списывается в базе, а ёмкость хранится в настройках личности — одной транзакцией их не связать. Поэтому итоговая
     * ёмкость запоминается до списания, списание и запись для мастера идут одним коммитом, а ёмкость ставится после. Процесс,
     * умерший посередине, доделывает апгрейд при следующем запуске ([resumeInterrupted]): токен не пропадает без прибавки RAM.
     */
    suspend fun apply(upgrade: Mb10Qr.RamUpgrade): Int? {
        if (tokens.isConsumed(upgrade.token)) return null
        val oldCapacity = identity.current?.ramCapacity ?: RAM_CAPACITY_DEFAULT
        val newCapacity = (oldCapacity + upgrade.delta).coerceIn(RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX)
        identity.beginRamUpgrade(upgrade.token, newCapacity)
        val applied = tx.inTransaction {
            if (tokens.insertIfAbsent(ConsumedTokenEntity(token = upgrade.token, consumedAt = System.currentTimeMillis())) == -1L) return@inTransaction false
            changes.record(ChangeField.RAM_CAPACITY, oldCapacity.toString(), newCapacity.toString(), ChangeReason.RAM_UPGRADE, sourceRef = upgrade.token)
            true
        }
        identity.finishRamUpgrade(newCapacity.takeIf { applied })
        return newCapacity.takeIf { applied }
    }

    /** Апгрейд, прерванный падением процесса: токен уже списан — ставим ёмкость; не списан — апгрейда не было, QR сработает снова. */
    suspend fun resumeInterrupted() {
        val (token, capacity) = identity.pendingRamUpgrade() ?: return
        val consumed = tokens.isConsumed(token)
        Mb10Log.event("RamUpgrade", "ram.resume", "token" to token, "capacity" to capacity, "consumed" to consumed)
        identity.finishRamUpgrade(capacity.takeIf { consumed })
    }
}
