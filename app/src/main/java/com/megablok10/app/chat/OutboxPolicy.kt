package com.megablok10.app.chat

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec

/**
 * Правила очереди исходящих сообщений (docs/network-spec.md, §7: при роуминге и обрывах сообщение не должно пропадать).
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

    /** Пауза перед очередной попыткой после [attempts] неудачных: 2, 4, 8, 15, 30 с, дальше раз в минуту. */
    private val BACKOFF_MS = longArrayOf(2_000, 4_000, 8_000, 15_000, 30_000, 60_000)
    fun nextDelayMs(attempts: Int): Long = BACKOFF_MS[attempts.coerceIn(0, BACKOFF_MS.lastIndex)]

    /** Сообщения старше этого срока перестают досылаться: через полдня они уже не имеют смысла в игре. */
    const val MAX_AGE_MS = 12L * 60 * 60 * 1000
}
