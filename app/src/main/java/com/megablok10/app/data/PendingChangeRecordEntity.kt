package com.megablok10.app.data

import androidx.room.Entity

/**
 * Локальная очередь неотправленных/неподтверждённых ChangeRecord (§3.4 ТЗ:
 * "ничего не удалять из локального журнала до подтверждения"). Строка
 * уходит из таблицы только когда коллектор подтвердил приём (id попал в
 * accepted) или явно отбраковал запись (rejected — почти наверняка баг
 * протокола, а не временная недоступность сети, повторять бессмысленно).
 * До того — переживает перезапуск приложения и уходит в очередной батч.
 */
@Entity(tableName = "pending_change_records", primaryKeys = ["id"])
data class PendingChangeRecordEntity(
    val id: String,
    val subjectKeyB64: String,
    val seq: Long,
    val happenedAt: Long,
    val field: String,
    val oldValue: String?,
    val newValue: String?,
    val reason: String,
    val sourceRef: String?,
    val actor: String,
    val signature: String,
)
