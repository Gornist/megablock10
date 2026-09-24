package com.megablok10.app.net

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Общая для TransactionStore и ItemTransferStore логика вокруг PENDING/DELIVERED
 * (см. PendingDelivery.kt) — покрыта здесь один раз чистыми юнит-тестами вместо
 * того, чтобы полагаться на то, что оба стораджа продолжат совпадать по коду.
 */
class PendingDeliveryTest {

    @Test fun `willSend false keeps the record pending without marking delivered`() {
        assertFalse(shouldMarkDeliveredBeforeSend(willSend = false))
    }

    @Test fun `willSend true marks delivered before attempting to send`() {
        assertTrue(shouldMarkDeliveredBeforeSend(willSend = true))
    }

    @Test fun `only NOT_REACHED rolls the delivery back to pending`() {
        assertTrue(shouldRevertToPendingAfterSend(SendOutcome.NOT_REACHED))
        assertFalse(shouldRevertToPendingAfterSend(SendOutcome.DELIVERED))
        assertFalse(shouldRevertToPendingAfterSend(SendOutcome.UNKNOWN))
    }

    @Test fun `UNKNOWN outcome stays delivered instead of rolling back — money or item must not end up on both sides`() {
        // Регрессия на конкретный сценарий из комментариев обоих стораджей: соединение было, но что-то
        // сломалось при отправке — карточка МОГЛА дойти, откатывать в PENDING (и тем самым разрешать
        // повторную отправку/отмену) нельзя, иначе получатель, реально получивший карточку, и отправитель,
        // отменивший или отправивший заново, оба остались бы с деньгами/предметом.
        assertFalse(shouldRevertToPendingAfterSend(SendOutcome.UNKNOWN))
    }

    @Test fun `own card is rejected regardless of the to field`() {
        assertEquals("своя же карточка", incomingCardRejection(fromPubKeyB64 = "me", toPubKeyB64 = "me", myPublicKeyB64 = "me"))
        assertEquals("своя же карточка", incomingCardRejection(fromPubKeyB64 = "me", toPubKeyB64 = "someone-else", myPublicKeyB64 = "me"))
    }

    @Test fun `card addressed to someone else is rejected — accepting it would create money or an item out of thin air`() {
        assertEquals("адресована не мне", incomingCardRejection(fromPubKeyB64 = "alice", toPubKeyB64 = "bob", myPublicKeyB64 = "me"))
    }

    @Test fun `card from someone else addressed to me is accepted`() {
        assertNull(incomingCardRejection(fromPubKeyB64 = "alice", toPubKeyB64 = "me", myPublicKeyB64 = "me"))
    }
}
