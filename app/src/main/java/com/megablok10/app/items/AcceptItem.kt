package com.megablok10.app.items

import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.sendReceipt
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr

/** Сценарий «принять предмет» — как [com.megablok10.app.wallet.AcceptPayment]: положить предмет в коллекцию и ответить чеком. */
class AcceptItem(private val ledger: ItemLedger, private val messenger: DirectMessenger) {
    /** true — предмет у игрока и чек ушёл отправителю. false — карточка отклонена (подпись, чужая, уже принята). */
    suspend operator fun invoke(me: Identity, card: Mb10Qr.ItemTransfer): Boolean {
        if (!ledger.acceptIncoming(me.publicKeyB64, card)) return false
        messenger.sendReceipt(me, card.fromPubKeyB64, ledger.buildReceipt(me, card.id))
        return true
    }
}
