package com.megablok10.app.collector

/**
 * Единица обмена с мастерским коллектором (admin-web/server) — см.
 * admin-web/README.md и ТЗ §2.2/§3.1. Зеркало серверного
 * src/lib/changeRecord.ts: те же поля, тот же формат подписи.
 *
 * oldValue/newValue — уже готовая строка (число или JSON.stringify сложного
 * значения), не структура: сервер сверяет подпись побайтово по тому, что
 * реально легло в HTTP-тело, не пересобирая её заново — так же, как
 * ClaimProtocol.signaturePayload для заявок на слоты. Если здесь положить
 * структуру и сериализовать её отдельно на каждом конце, подписи разойдутся
 * из-за разницы JSON-сериализаторов Kotlin/JS.
 */
data class ChangeRecord(
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

/** Байты, которые подписываются — тот же плоский pipe-формат, что signaturePayload на сервере (admin-web/server/src/lib/changeRecord.ts). */
fun ChangeRecord.signaturePayload(): ByteArray {
    val parts = listOf(
        id, subjectKeyB64, seq.toString(), happenedAt.toString(), field,
        oldValue ?: "", newValue ?: "", reason, sourceRef ?: "", actor,
    )
    return parts.joinToString("|").toByteArray(Charsets.UTF_8)
}
