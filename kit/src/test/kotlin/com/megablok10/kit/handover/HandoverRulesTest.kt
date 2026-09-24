package com.megablok10.kit.handover

import com.megablok10.kit.net.SendOutcome
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Правила протокола передачи вокруг PENDING/DELIVERED — покрыты здесь один раз чистыми юнит-тестами вместо того, чтобы
 * полагаться на то, что журналы денег и предметов продолжат совпадать по коду.
 */
class HandoverRulesTest {

    @Test fun `willSend false keeps the record pending without marking delivered`() {
        assertFalse(HandoverRules.shouldMarkDeliveredBeforeSend(willSend = false))
    }

    @Test fun `willSend true marks delivered before attempting to send`() {
        assertTrue(HandoverRules.shouldMarkDeliveredBeforeSend(willSend = true))
    }

    @Test fun `only NOT_REACHED rolls the delivery back to pending`() {
        assertTrue(HandoverRules.shouldRevertToPendingAfterSend(SendOutcome.NOT_REACHED))
        assertFalse(HandoverRules.shouldRevertToPendingAfterSend(SendOutcome.DELIVERED))
        assertFalse(HandoverRules.shouldRevertToPendingAfterSend(SendOutcome.UNKNOWN))
    }

    @Test fun `UNKNOWN outcome stays delivered instead of rolling back — value must not end up on both sides`() {
        // Соединение было, но что-то сломалось при отправке — карточка МОГЛА дойти, откатывать в PENDING (и тем самым
        // разрешать повторную отправку/отмену) нельзя, иначе получатель, реально получивший карточку, и отправитель,
        // отменивший или отправивший заново, оба остались бы с ценностью.
        assertFalse(HandoverRules.shouldRevertToPendingAfterSend(SendOutcome.UNKNOWN))
    }

    @Test fun `own card is rejected regardless of the to field`() {
        assertEquals("своя же карточка", HandoverRules.incomingCardRejection(fromPubKeyB64 = "me", toPubKeyB64 = "me", myPublicKeyB64 = "me"))
        assertEquals("своя же карточка", HandoverRules.incomingCardRejection(fromPubKeyB64 = "me", toPubKeyB64 = "someone-else", myPublicKeyB64 = "me"))
    }

    @Test fun `card addressed to someone else is rejected — accepting it would create value out of thin air`() {
        assertEquals("адресована не мне", HandoverRules.incomingCardRejection(fromPubKeyB64 = "alice", toPubKeyB64 = "bob", myPublicKeyB64 = "me"))
    }

    @Test fun `card from someone else addressed to me is accepted`() {
        assertNull(HandoverRules.incomingCardRejection(fromPubKeyB64 = "alice", toPubKeyB64 = "me", myPublicKeyB64 = "me"))
    }

    @Test fun `rejectIncoming checks addressing first, then the sender's signature`() {
        var verified = 0
        val ok: (String, ByteArray, String) -> Boolean = { _, _, _ -> verified++; true }
        val bad: (String, ByteArray, String) -> Boolean = { _, _, _ -> verified++; false }
        assertEquals("адресована не мне", HandoverRules.rejectIncoming("alice", "bob", "me", ByteArray(0), "sig", ok))
        assertEquals(0, verified) // до проверки подписи не дошло
        assertEquals("подпись не сошлась", HandoverRules.rejectIncoming("alice", "me", "me", ByteArray(0), "sig", bad))
        assertNull(HandoverRules.rejectIncoming("alice", "me", "me", ByteArray(0), "sig", ok))
    }

    @Test fun `receipt payload format is id pipe receiver`() {
        assertArrayEquals("tx-1|recvPub==".toByteArray(), HandoverRules.receiptSignaturePayload("tx-1", "recvPub=="))
    }
}
