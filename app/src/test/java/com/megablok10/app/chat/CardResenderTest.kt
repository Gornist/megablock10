package com.megablok10.app.chat

import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** Застрявшая карточка уходит снова — только видимому адресату и только тем же сообщением, что в первый раз. */
class CardResenderTest {
    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val carol = TestPlayer("Carol")
    private val sent = mutableListOf<Pair<String, ChatWireMessage>>()
    private fun original(to: String, id: String) =
        ChatWireMessage(ChatMessageType.DM, alice.key, "Alice", "Малстром", to, 1_000L, "MB10:TX:v2:$id:…")

    private fun resender(stuck: List<StuckCard>, visible: List<TestPlayer>, me: String? = alice.key, known: Set<String> = stuck.map { it.id }.toSet()) = CardResender(
        stuck = { stuck },
        originalMessage = { _, to, id -> original(to, id).takeIf { id in known } },
        send = { to, msg -> sent += to to msg; true },
        online = { key -> visible.any { it.key == key } },
        me = { me },
    )

    @Test fun onlyVisibleRecipientsGetTheOriginalMessageAgain() = runTest {
        val n = resender(listOf(StuckCard("tx-1", bob.key), StuckCard("tx-2", carol.key)), visible = listOf(bob)).resendOnce()
        assertEquals(1, n)
        assertEquals(listOf(bob.key to original(bob.key, "tx-1")), sent)
    }

    @Test fun cardWithoutItsOriginalMessageIsSkipped() = runTest {
        assertEquals(0, resender(listOf(StuckCard("tx-1", bob.key)), visible = listOf(bob), known = emptySet()).resendOnce())
        assertEquals(emptyList<Any>(), sent)
    }

    @Test fun withoutIdentityNothingIsSent() = runTest {
        assertEquals(0, resender(listOf(StuckCard("tx-1", bob.key)), visible = listOf(bob), me = null).resendOnce())
    }
}
