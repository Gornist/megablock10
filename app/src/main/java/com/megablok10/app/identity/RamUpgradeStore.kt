package com.megablok10.app.identity

import android.content.Context
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.data.ConsumedTokenEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.qr.Mb10Qr

/**
 * Применяет Mb10Qr.RamUpgrade к Identity.ramCapacity этого устройства ровно
 * один раз на токен — если карточку с QR сфотографируют и просканируют с
 * трёх разных телефонов, применится на каждом по разу (RAM хранится локально
 * на устройстве, не у сервера), но повторный скан ТОГО ЖЕ токена ТЕМ ЖЕ
 * устройством второй раз не сработает.
 */
object RamUpgradeStore {
    /** null — токен уже был применён на этом устройстве раньше; иначе — новая ёмкость буфера. */
    suspend fun apply(context: Context, upgrade: Mb10Qr.RamUpgrade): Int? {
        val rowId = Mb10Database.get(context).consumedTokenDao().insertIfAbsent(
            ConsumedTokenEntity(token = upgrade.token, consumedAt = System.currentTimeMillis())
        )
        if (rowId == -1L) return null
        val oldCapacity = IdentityManager.current(context)?.ramCapacity ?: RAM_CAPACITY_DEFAULT
        val newCapacity = IdentityManager.applyRamUpgrade(context, upgrade.delta)
        ChangeRecordStore.enqueue(context, ChangeField.RAM_CAPACITY, oldCapacity.toString(), newCapacity.toString(), ChangeReason.RAM_UPGRADE, sourceRef = upgrade.token)
        return newCapacity
    }
}
