package com.megablok10.app.ui.screens

import com.megablok10.app.data.TransactionStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Кнопка «Принять» на карточке перевода: только на чужой и ещё не принятой (живая проверка 05.10: у принятого перевода кнопка оставалась). */
class ChatCardAcceptTest {
    @Test fun incomingCardWithoutLocalRecordCanBeAccepted() {
        assertTrue(incomingCardNeedsAccept(self = false, localStatus = null))
    }

    @Test fun alreadyAcceptedIncomingCardShowsNoButton() {
        assertFalse(incomingCardNeedsAccept(self = false, localStatus = TransactionStatus.CONFIRMED))
    }

    @Test fun ownCardNeverHasAcceptButton() {
        assertFalse(incomingCardNeedsAccept(self = true, localStatus = null))
        assertFalse(incomingCardNeedsAccept(self = true, localStatus = TransactionStatus.DELIVERED))
    }
}
