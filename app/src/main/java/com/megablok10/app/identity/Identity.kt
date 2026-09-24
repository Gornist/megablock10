package com.megablok10.app.identity

/** Стартовая и максимальная ёмкость буфера взлома (см. ревизию v9 §2 — раньше это была глобальная константа MockBreach.ramCapacity). */
const val RAM_CAPACITY_DEFAULT = 6
const val RAM_CAPACITY_MAX = 13

/**
 * Персонаж на этом устройстве, каким его видят остальные части приложения. publicKeyB64 — первичный идентификатор во всей
 * системе (контакты, шарды, транзакции, записи для мастера); хранит и меняет личность [IdentityStore].
 *
 * toString() — стандартный для data class: стенд e2e вытаскивает ключ из строки `set applied: Identity(publicKeyB64=…, …)`
 * (scripts/e2e/lib.sh, pk_of), поэтому имя поля и форму класса не менять.
 */
data class Identity(
    val publicKeyB64: String,
    val callsign: String,
    val faction: String,
    val ramCapacity: Int = RAM_CAPACITY_DEFAULT
)
