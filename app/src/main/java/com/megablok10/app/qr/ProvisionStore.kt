package com.megablok10.app.qr

import android.content.Context
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.wallet.TransactionStore

/** Итог применения QR персонажа. */
sealed interface ProvisionResult {
    data class Applied(val identity: Identity) : ProvisionResult
    /** Персонаж на телефоне уже есть: повторно можно только после сброса сессии (Настройки → «Опасная зона»). */
    object AlreadyHasIdentity : ProvisionResult
    /** Этот QR на этом телефоне уже применяли: новый выдаёт мастер. */
    object AlreadyUsed : ProvisionResult
    data class Invalid(val message: String) : ProvisionResult
}

/**
 * Первый запуск по QR мастера (docs/provisioning-qr.md): один код настраивает сервер и код игры и создаёт персонажа с позывным, фракцией,
 * стартовым балансом и ёмкостью буфера. Порядок важен: сначала настройки сервера, потом личность — чтобы записи о создании персонажа
 * сразу ушли по нужному адресу и с нужным кодом игры.
 */
object ProvisionStore {
    suspend fun apply(context: Context, p: Mb10Qr.Provision): ProvisionResult {
        ProvisionRules.validate(p)?.let { return ProvisionResult.Invalid(it) }
        if (IdentityManager.hasIdentity(context)) return ProvisionResult.AlreadyHasIdentity
        if (CollectorSettings.isProvisionUsed(context, p.id)) return ProvisionResult.AlreadyUsed

        CollectorSettings.markProvisionUsed(context, p.id)
        if (p.collectorUrl.isNotEmpty()) CollectorSettings.setBaseUrl(context, p.collectorUrl)
        if (p.gameSecret.isNotEmpty()) CollectorSettings.setGameSecret(context, p.gameSecret)
        CollectorSettings.setProvisioned(context, p.collectorUrl.isNotEmpty() || p.gameSecret.isNotEmpty())

        val created = IdentityManager.getOrCreate(context, p.callsign.trim(), p.faction.trim())
        ChangeRecordStore.enqueue(context, ChangeField.CALLSIGN, null, created.callsign, ChangeReason.CHARACTER_CREATED)
        ChangeRecordStore.enqueue(context, ChangeField.FACTION, null, created.faction, ChangeReason.CHARACTER_CREATED)
        if (p.ramCapacity != 0 && p.ramCapacity != created.ramCapacity) {
            IdentityManager.applyRamOverride(context, p.ramCapacity)
            ChangeRecordStore.enqueue(context, ChangeField.RAM_CAPACITY, created.ramCapacity.toString(), p.ramCapacity.toString(), ChangeReason.CHARACTER_CREATED)
        }
        TransactionStore.setStartingBalance(context, p.id, p.startBalance)
        return ProvisionResult.Applied(IdentityManager.current(context) ?: created)
    }
}
