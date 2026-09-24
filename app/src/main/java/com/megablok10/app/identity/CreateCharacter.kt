package com.megablok10.app.identity

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.kit.sync.ChangeRecorder

/**
 * Сценарий «создать персонажа вручную» (сборка для разработки и стенд e2e; на игре персонажа выдаёт мастер QR-кодом — ProvisionStore):
 * ключи и профиль на устройстве плюс записи CHARACTER_CREATED для дашборда, чтобы мастер увидел появление позывного и фракции.
 * Если персонаж уже есть, он возвращается как есть и записей не будет.
 */
class CreateCharacter(private val identity: IdentityStore, private val changes: ChangeRecorder) {
    suspend operator fun invoke(callsign: String, faction: String): Identity {
        val isNew = !identity.hasIdentity()
        val created = identity.getOrCreate(callsign, faction)
        if (isNew) {
            changes.record(ChangeField.CALLSIGN, null, created.callsign, ChangeReason.CHARACTER_CREATED)
            changes.record(ChangeField.FACTION, null, created.faction, ChangeReason.CHARACTER_CREATED)
        }
        return created
    }
}
