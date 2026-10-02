package com.megablok10.app.netrun

import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.sendReceipt
import com.megablok10.app.identity.Identity
import com.megablok10.app.items.ItemLedger
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.wallet.PaymentLedger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

private const val TAG = "Netrun"

/**
 * Автоприём добычи от Моста «Сети» (M3): карточки предметов (добыча, вернувшиеся демоны) и эдди, пришедшие от ключа мира из QR
 * стойки, принимаются без ручного «Принять» — игрок в очках и не может нажимать кнопки в треде. Принимают те же журналы
 * ([ItemLedger.acceptIncoming]/[PaymentLedger.recordIncoming]: проверка подписи и адресата); чек уходит отдельно, в [work]. От всех остальных отправителей поведение прежнее:
 * карточка ждёт «Принять» в треде.
 *
 * Повтор карточки (Мост досылает её, пока нет чека) не принимается второй раз, но чек уходит снова — если карточка уже принята:
 * прошлый чек мог не дойти, и без него выдача висела бы у Моста вечно.
 */
class WorldAutoAccept(
    private val worldKey: () -> String?,
    private val items: ItemLedger,
    private val payments: PaymentLedger,
    private val messenger: DirectMessenger,
    /** Скоуп процесса: чек уходит из него, уже после того как обработчик сохранил карточку и вернулся (правило D2: «доставлено» — после сохранения). */
    private val work: CoroutineScope,
) {
    /** true — сообщение было карточкой от Моста и разобрано здесь (принята или отклонена); false — это не наш случай. */
    suspend fun onDirect(me: Identity, message: ChatWireMessage): Boolean {
        val world = worldKey() ?: return false
        if (message.type != ChatMessageType.DM || message.fromPubKeyB64 != world || message.toPubKeyB64 != me.publicKeyB64) return false
        return when (val card = Mb10QrCodec.decode(message.body)) {
            is Mb10Qr.ItemTransfer -> card.fromPubKeyB64 == world && handleItem(me, world, card)
            is Mb10Qr.Transaction -> card.fromPubKeyB64 == world && handlePayment(me, world, card)
            else -> false
        }
    }

    private suspend fun handleItem(me: Identity, world: String, card: Mb10Qr.ItemTransfer): Boolean {
        val accepted = items.acceptIncoming(me.publicKeyB64, card)
        val repeat = !accepted && items.hasIncoming(card.id)
        if (accepted || repeat) sendReceiptLater(me, world, items.buildReceipt(me, card.id))
        Mb10Log.event(TAG, "netrun.world_item", "id" to card.id, "kind" to card.kind.name, "accepted" to accepted, "repeat" to repeat)
        return true
    }

    private suspend fun handlePayment(me: Identity, world: String, card: Mb10Qr.Transaction): Boolean {
        val accepted = payments.recordIncoming(me.publicKeyB64, card)
        val repeat = !accepted && payments.hasIncoming(card.id)
        if (accepted || repeat) sendReceiptLater(me, world, payments.buildReceipt(me, card.id))
        Mb10Log.event(TAG, "netrun.world_eddies", "id" to card.id, "amount" to card.amount, "accepted" to accepted, "repeat" to repeat)
        return true
    }

    private fun sendReceiptLater(me: Identity, world: String, receipt: Mb10Qr.Receipt) {
        work.launch { messenger.sendReceipt(me, world, receipt) }
    }
}
