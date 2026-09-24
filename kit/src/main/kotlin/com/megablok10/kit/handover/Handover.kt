package com.megablok10.kit.handover

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.net.SendOutcome

/**
 * Журнал исходящих карточек одного вида передач — порт: приложение даёт реализацию поверх своей таблицы (у Мегаблока —
 * `transactions` для денег и `item_transfers` для предметов). Переходы условные: каждый меняет статус, только если запись
 * сейчас в нужном состоянии, и возвращает число изменённых строк (0 — перехода не было).
 */
interface OutgoingJournal {
    /** PENDING → DELIVERED. */
    suspend fun markDelivered(id: String): Int

    /** DELIVERED → PENDING (карточка точно не ушла). */
    suspend fun markUndelivered(id: String): Int

    /** PENDING/DELIVERED → CONFIRMED (пришёл чек). */
    suspend fun confirm(id: String): Int

    /** Кому адресована карточка [id] — чек принимается только от него; null — такой записи нет. */
    suspend fun recipientOf(id: String): String?
}

/**
 * Сторона отправителя в протоколе передачи ([HandoverRules]): доставка карточки так, чтобы отмену нельзя было провести
 * одновременно с доставкой, и фиксация передачи по чеку получателя. Один экземпляр на вид передач.
 *
 * [eventPrefix] — префикс событий журнала (`tx` → `tx.deliver`, `tx.receipt`; `item` → `item.deliver`…), [tag] — тег журнала.
 */
class Handover(
    private val journal: OutgoingJournal,
    private val log: KitLog = NoopLog,
    private val tag: String = "Handover",
    private val eventPrefix: String = "handover",
    private val verify: (publicKeyB64: String, data: ByteArray, signatureB64: String) -> Boolean = Ecdsa::verify,
) {
    /**
     * Отправляет карточку получателю: статус DELIVERED ставится ДО отправки (иначе «отменить» во время полёта карточки
     * оставило бы ценность у обоих) и откатывается в PENDING, только если соединиться точно не удалось
     * ([SendOutcome.NOT_REACHED]). [willSend] = false — получатель офлайн: [send] всё равно зовётся (он может, например,
     * сохранить карточку в локальный тред), но запись остаётся PENDING и отменяемой.
     */
    suspend fun deliver(id: String, willSend: Boolean, send: suspend () -> SendOutcome) {
        if (!HandoverRules.shouldMarkDeliveredBeforeSend(willSend)) {
            send()
            log.event(tag, "$eventPrefix.deliver", "id" to id, "peerVisible" to false, "status" to "остаётся PENDING")
            return
        }
        journal.markDelivered(id)
        val outcome = send()
        val reverted = HandoverRules.shouldRevertToPendingAfterSend(outcome)
        if (reverted) journal.markUndelivered(id)
        log.event(tag, "$eventPrefix.deliver", "id" to id, "peerVisible" to true, "outcome" to outcome.name, "status" to if (reverted) "откат в PENDING" else "DELIVERED")
    }

    /**
     * Фиксирует передачу [expectedId] по чеку получателя — с этого момента отменить её уже нельзя. Чек принимается, только
     * если он про эту передачу, подписан именно её адресатом (иначе любой контакт мог бы «подтвердить» чужую передачу и тем
     * заблокировать её отмену) и подпись сходится. true — статус перешёл в CONFIRMED сейчас.
     */
    suspend fun confirmByReceipt(expectedId: String, receiptId: String, receiverPubKeyB64: String, signatureB64: String): Boolean {
        if (receiptId != expectedId) return false
        if (journal.recipientOf(receiptId) != receiverPubKeyB64) return false
        if (!verify(receiverPubKeyB64, HandoverRules.receiptSignaturePayload(receiptId, receiverPubKeyB64), signatureB64)) return false
        val confirmed = journal.confirm(receiptId) > 0
        log.event(tag, "$eventPrefix.receipt", "id" to receiptId, "confirmed" to confirmed)
        return confirmed
    }
}
