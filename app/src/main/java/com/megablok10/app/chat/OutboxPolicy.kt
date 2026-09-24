package com.megablok10.app.chat

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec

/**
 * Что можно ставить в очередь исходящих (docs/network-spec.md, §7: при роуминге и обрывах сообщение не должно пропадать).
 * Сама механика очереди и график повторов — kit Outbox/OutboxSchedule (2, 4, 8, 15, 30 с, дальше раз в минуту; 12 часов срок).
 *
 * Деньги и передачи предметов в очередь НЕ попадают: их карточку можно отменить, пока получатель её не получил (см.
 * TransactionStore.deliverOutgoing), а автодоставка «потом, сама» доставила бы карточку уже отменённого платежа — и получатель
 * принял бы деньги, которые отправителю вернули. Чек получателя, обычный текст и фракционный чат безопасны: повтор идемпотентен.
 */
object OutboxPolicy {
    fun isQueueable(body: String): Boolean = when (Mb10QrCodec.decode(body)) {
        is Mb10Qr.Transaction, is Mb10Qr.ItemTransfer -> false
        else -> true
    }
}
