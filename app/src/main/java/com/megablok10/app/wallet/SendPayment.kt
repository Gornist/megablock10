package com.megablok10.app.wallet

import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.deliverCard
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import java.util.UUID

/**
 * Сценарий «перевести деньги игроку» — один и тот же из «Финансов», из треда чата и со стенда e2e: подписать карточку, списать
 * сумму (PENDING, одной транзакцией с проверкой баланса) и отправить карточку адресату личным сообщением. Если адресат не в сети,
 * карточка ложится в свой тред, а перевод остаётся PENDING — его можно отменить, пока карточка не доставлена.
 */
class SendPayment(private val ledger: PaymentLedger, private val messenger: DirectMessenger) {
    /**
     * Карточка перевода или null — отказ до списания (не хватает денег, сумма некорректна): ничего не списано и не отправлено.
     * [offline] — считать адресата невидимым (стенд e2e).
     */
    suspend operator fun invoke(
        me: Identity,
        toPubKeyB64: String,
        amount: Long,
        memo: String,
        id: String = UUID.randomUUID().toString(),
        offline: Boolean = false,
    ): Mb10Qr.Transaction? {
        val tx = ledger.signedTransaction(me, toPubKeyB64, amount, memo, id)
        if (!ledger.recordOutgoingPending(tx, toPubKeyB64)) return null
        messenger.deliverCard(me, toPubKeyB64, Mb10QrCodec.encodeTransaction(tx), offline) { willSend, send ->
            ledger.deliverOutgoing(tx.id, willSend, send)
        }
        return tx
    }
}
