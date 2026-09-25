package com.megablok10.app.chat

import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Карточка перевода или предмета, доставленная адресату (DELIVERED), но так и не подтверждённая его чеком. */
data class StuckCard(val id: String, val toPubKeyB64: String)

/**
 * Переотправка застрявших карточек. Статус DELIVERED ставится до отправки и остаётся, если соединение прошло, — но «записали в
 * сокет» не значит «получатель сохранил»: телефон адресата мог упасть, не записав карточку. Отменить такую передачу нельзя
 * (иначе ценность осталась бы у обоих), и без переотправки она висела бы вечно.
 *
 * Раз в [INTERVAL_MS] карточки старше [GRACE_MS] уходят адресату снова, если он сейчас виден, — тем же сообщением, что и в
 * первый раз (то же время и текст): у получателя, который её уже сохранил, повтор отбрасывается как дубль, а у потерявшего —
 * появляется в треде. Чек за принятую карточку и так ходит через очередь исходящих (OutboxPolicy), поэтому здесь его нет.
 * Для DELIVERED это безопасно: в отличие от PENDING, её уже нельзя отменить, и повтор не доставит отменённое.
 */
class CardResender(
    private val stuck: suspend (createdBefore: Long) -> List<StuckCard>,
    private val originalMessage: suspend (me: String, to: String, transferId: String) -> ChatWireMessage?,
    private val send: suspend (toPubKeyB64: String, ChatWireMessage) -> Boolean,
    private val online: (pubKeyB64: String) -> Boolean,
    private val me: () -> String?,
    private val now: () -> Long = System::currentTimeMillis,
) {
    /** Один проход: сколько карточек ушло снова. */
    suspend fun resendOnce(): Int {
        val myKey = me() ?: return 0
        // Только адресатам, которых сейчас видно, и только если исходное сообщение с карточкой ещё лежит в своём треде.
        val due = stuck(now() - GRACE_MS).mapNotNull { card ->
            if (!online(card.toPubKeyB64)) return@mapNotNull null
            originalMessage(myKey, card.toPubKeyB64, card.id)?.let { card to it }
        }
        return due.count { (card, message) ->
            send(card.toPubKeyB64, message).also { ok -> Mb10Log.event(TAG, "card.resend", "id" to card.id, "to" to Mb10Log.short(card.toPubKeyB64), "ok" to ok) }
        }
    }

    /** Фоновый цикл сетевой сессии (MeshSession, sessionTasks). */
    fun start(scope: CoroutineScope) {
        scope.launch {
            while (isActive) {
                delay(INTERVAL_MS)
                try {
                    resendOnce()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Mb10Log.w(TAG, "переотправка карточек упала: ${e.message}", e)
                }
            }
        }
    }

    companion object {
        private const val TAG = "CardResend"
        /** Сколько ждать чека, прежде чем считать карточку застрявшей: обычно получатель отвечает за секунды. */
        const val GRACE_MS = 60_000L
        const val INTERVAL_MS = 60_000L
    }
}
