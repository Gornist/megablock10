package com.megablok10.app.collector

import com.megablok10.app.identity.RAM_CAPACITY_DEFAULT
import com.megablok10.app.identity.RAM_CAPACITY_MAX
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.MasterApply

/**
 * Правка мастера, разобранная до применения. Значение, которое не удаётся разобрать, — не «пропустить молча», а явный отказ
 * ([MasterApply.Failed], permanent: повтор того же значения не поможет): сервер покажет его мастеру, а не будет считать применённым.
 */
sealed interface MasterOverride {
    data class Balance(val value: Long, val memo: String) : MasterOverride
    data class Ram(val value: Int) : MasterOverride
    data class Callsign(val value: String) : MasterOverride
    data class Faction(val value: String) : MasterOverride
    data class Announcement(val text: String) : MasterOverride

    /** Применять нечего: значение не разобралось. [failure] уходит серверу вместо подтверждения. */
    data class Invalid(val failure: MasterApply.Failed) : MasterOverride

    companion object {
        /** Разобранная правка или [Invalid] с причиной для мастера. Чистая функция — покрыта тестами без Android. */
        fun parse(change: ChangeRecord): MasterOverride {
            val value = change.newValue ?: return fail("правка без значения")
            return when (change.field) {
                ChangeField.BALANCE -> value.toLongOrNull()?.let { Balance(it, change.sourceRef ?: "без основания") }
                    ?: fail("баланс — не целое число: «$value»")
                ChangeField.RAM_CAPACITY -> value.toIntOrNull()?.takeIf { it in RAM_CAPACITY_DEFAULT..RAM_CAPACITY_MAX }?.let(::Ram)
                    ?: fail("RAM — не число от $RAM_CAPACITY_DEFAULT до $RAM_CAPACITY_MAX: «$value»")
                ChangeField.CALLSIGN -> value.trim().takeIf { it.isNotEmpty() }?.let(::Callsign) ?: fail("пустой позывной")
                ChangeField.FACTION -> value.trim().takeIf { it.isNotEmpty() }?.let(::Faction) ?: fail("пустая фракция")
                ChangeField.ANNOUNCEMENT -> Announcement(value)
                else -> fail("поле «${change.field}» не поддерживается этой версией приложения")
            }
        }

        private fun fail(reason: String) = Invalid(MasterApply.Failed(reason, permanent = true))
    }
}
