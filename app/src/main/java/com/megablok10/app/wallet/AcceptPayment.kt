package com.megablok10.app.wallet

import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.sendReceipt
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr

/**
 * Сценарий «принять перевод» (кнопка «Принять» в треде, стенд e2e): зачислить деньги и сразу ответить отправителю чеком — без
 * чека его перевод так и останется «доставлен, ждёт принятия». Повторное «Принять» на той же карточке ничего не зачисляет.
 */
class AcceptPayment(private val ledger: PaymentLedger, private val messenger: DirectMessenger) {
    /** true — деньги зачислены и чек ушёл (или лёг в тред, если отправителя сейчас не видно). false — карточка отклонена. */
    suspend operator fun invoke(me: Identity, tx: Mb10Qr.Transaction): Boolean {
        if (!ledger.recordIncoming(me.publicKeyB64, tx)) return false
        messenger.sendReceipt(me, tx.fromPubKeyB64, ledger.buildReceipt(me, tx.id))
        return true
    }
}
