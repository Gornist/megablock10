package com.megablok10.app.collector

/**
 * Поля записей Мегаблока для мастерского сервера (kit ChangeRecord.field) — те же строки, что понимает дашборд
 * (admin-web/server/src/lib/changeRecord.ts). Переименовывать нельзя: история на сервере и подписи хранят их как есть.
 */
object ChangeField {
    const val BALANCE = "balance"
    const val RAM_CAPACITY = "ramCapacity"
    const val CALLSIGN = "callsign"
    const val FACTION = "faction"
    const val DAEMONS_ADD = "daemons.add"
    const val DAEMONS_REMOVE = "daemons.remove"
    const val SHARDS_ADD = "shards.add"
    const val SHARDS_REMOVE = "shards.remove"
    const val SHARDS_DECRYPT = "shards.decrypt"
    const val COUNTERS_BREACH = "counters.breach"
    const val COUNTERS_ALERT = "counters.alert"
    const val COUNTERS_BLOCKED = "counters.blocked"

    /** Только от мастера (дашборд → устройство): текст объявления. Устройство такие записи не создаёт. */
    const val ANNOUNCEMENT = "announcement"
}

/** Причины изменений (kit ChangeRecord.reason) — те же строки, что на сервере. */
object ChangeReason {
    const val CHARACTER_CREATED = "CHARACTER_CREATED"
    const val BREACH_ATTEMPT = "BREACH_ATTEMPT"
    const val BREACH_BLOCKED = "BREACH_BLOCKED"
    const val BREACH_LOOT = "BREACH_LOOT"
    const val BREACH_EDDIES = "BREACH_EDDIES"
    const val SHARD_SCAN = "SHARD_SCAN"
    const val SHARD_DECRYPT = "SHARD_DECRYPT"
    const val TRANSFER_OUT = "TRANSFER_OUT"
    const val TRANSFER_IN = "TRANSFER_IN"
    const val TRANSFER_CANCELLED = "TRANSFER_CANCELLED"
    const val ITEM_TRANSFER_OUT = "ITEM_TRANSFER_OUT"
    const val ITEM_TRANSFER_IN = "ITEM_TRANSFER_IN"
    const val ITEM_TRANSFER_CANCELLED = "ITEM_TRANSFER_CANCELLED"
    const val RAM_UPGRADE = "RAM_UPGRADE"
    const val ALERT_SENT = "ALERT_SENT"
    const val ALERT_SUPPRESSED = "ALERT_SUPPRESSED"
    const val MASTER_OVERRIDE = "MASTER_OVERRIDE"
    const val CHARACTER_RESET = "CHARACTER_RESET"
}
