package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

object TransactionStatus {
    /** Записан локально, но карточка получателю НЕ доставлена (он офлайн / отправка не удалась) — отменить ещё можно. */
    const val PENDING = "PENDING"
    /** Карточка ушла получателю — он уже мог нажать "Принять", поэтому отмена запрещена (иначе сумма окажется у обоих). */
    const val DELIVERED = "DELIVERED"
    const val CONFIRMED = "CONFIRMED"
}

/**
 * Одна запись в локальном денежном журнале устройства. amount со знаком —
 * баланс персонажа это просто сумма amount по всем записям, отдельного
 * поля-счётчика нет. counterpartyPubKeyB64 пустой для собственных исходящих
 * платежей — в момент генерации QR плательщик ещё не знает, кто его
 * отсканирует (как с передачей наличных из рук в руки).
 *
 * status у исходящей записи начинается как PENDING (деньги уже списаны, но
 * отправитель ещё может отменить — если платёж не удался) и становится
 * CONFIRMED только когда отправитель отсканировал чек получателя. После
 * CONFIRMED отменить нельзя — это и есть проверка, что перевод реально
 * состоялся, а не просто "деньги списались и пропали в никуда". Входящие
 * записи у получателя сразу CONFIRMED: получив деньги, отменять ему нечего.
 */
// observeAll() сортирует по timestamp DESC на каждый снимок кошелька — без индекса это полный скан таблицы.
@Entity(tableName = "transactions", indices = [Index("timestamp")])
data class TransactionEntity(
    @PrimaryKey val id: String,
    val counterpartyPubKeyB64: String,
    val amount: Long,
    val memo: String,
    val timestamp: Long,
    val status: String
)
