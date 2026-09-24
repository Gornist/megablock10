package com.megablok10.app.qr

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.wallet.TransactionStore
import com.megablok10.kit.sync.ChangeRecorder

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
class ProvisionStore(
    private val identity: IdentityStore,
    private val settings: CollectorSettings,
    private val changes: ChangeRecorder,
    private val wallet: TransactionStore,
) {
    suspend fun apply(p: Mb10Qr.Provision): ProvisionResult {
        val tag = "Provision"
        ProvisionRules.validate(p)?.let { Mb10Log.warnEvent(tag, "provision.invalid", "id" to p.id, "why" to it); return ProvisionResult.Invalid(it) }
        if (identity.hasIdentity()) { Mb10Log.warnEvent(tag, "provision.refused", "id" to p.id, "why" to "личность уже есть"); return ProvisionResult.AlreadyHasIdentity }
        if (settings.isProvisionUsed(p.id)) { Mb10Log.warnEvent(tag, "provision.refused", "id" to p.id, "why" to "код уже применялся на этом телефоне"); return ProvisionResult.AlreadyUsed }
        Mb10Log.event(tag, "provision.apply", "id" to p.id, "callsign" to p.callsign, "faction" to p.faction, "balance" to p.startBalance, "ram" to p.ramCapacity, "server" to p.collectorUrl.ifEmpty { "из сборки" }, "secretSet" to p.gameSecret.isNotEmpty())

        settings.markProvisionUsed(p.id)
        if (p.collectorUrl.isNotEmpty()) settings.setBaseUrl(p.collectorUrl)
        if (p.gameSecret.isNotEmpty()) settings.setGameSecret(p.gameSecret)
        settings.setProvisioned(p.collectorUrl.isNotEmpty() || p.gameSecret.isNotEmpty())

        val created = identity.getOrCreate(p.callsign.trim(), p.faction.trim())
        changes.record(ChangeField.CALLSIGN, null, created.callsign, ChangeReason.CHARACTER_CREATED, sourceRef = p.id)
        changes.record(ChangeField.FACTION, null, created.faction, ChangeReason.CHARACTER_CREATED, sourceRef = p.id)
        if (p.ramCapacity != 0 && p.ramCapacity != created.ramCapacity) {
            identity.applyRamOverride(p.ramCapacity)
            changes.record(ChangeField.RAM_CAPACITY, created.ramCapacity.toString(), p.ramCapacity.toString(), ChangeReason.CHARACTER_CREATED, sourceRef = p.id)
        }
        wallet.setStartingBalance(p.id, p.startBalance)
        Mb10Log.event(tag, "provision.done", "id" to p.id, "me" to Mb10Log.short(created.publicKeyB64))
        return ProvisionResult.Applied(identity.current ?: created)
    }
}
