package com.megablok10.app.identity

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.ConsumedTokenDao
import com.megablok10.app.data.ConsumedTokenEntity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.sync.ChangeRecorder

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
) {
    /** null — токен уже был применён на этом устройстве раньше; иначе — новая ёмкость буфера. */
    suspend fun apply(upgrade: Mb10Qr.RamUpgrade): Int? {
        val rowId = tokens.insertIfAbsent(ConsumedTokenEntity(token = upgrade.token, consumedAt = System.currentTimeMillis()))
        if (rowId == -1L) return null
        val oldCapacity = identity.current?.ramCapacity ?: RAM_CAPACITY_DEFAULT
        val newCapacity = identity.applyRamUpgrade(upgrade.delta)
        changes.record(ChangeField.RAM_CAPACITY, oldCapacity.toString(), newCapacity.toString(), ChangeReason.RAM_UPGRADE, sourceRef = upgrade.token)
        return newCapacity
    }
}
