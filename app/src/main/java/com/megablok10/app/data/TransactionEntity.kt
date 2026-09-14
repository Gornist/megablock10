package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Одна запись в локальном денежном журнале устройства. amount со знаком —
 * баланс персонажа это просто сумма amount по всем записям, отдельного
 * поля-счётчика нет. counterpartyPubKeyB64 пустой для собственных исходящих
 * платежей — в момент генерации QR плательщик ещё не знает, кто его
 * отсканирует (как с передачей наличных из рук в руки).
 */
@Entity(tableName = "transactions")
data class TransactionEntity(
    @PrimaryKey val id: String,
    val counterpartyPubKeyB64: String,
    val amount: Long,
    val memo: String,
    val timestamp: Long
)
