package com.megablok10.netrun.bridge

import com.megablok10.kit.net.SendOutcome
import com.megablok10.netrun.bridge.phone.PhoneSender
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Отправка решённых `run.breach` сигналов СБ: документ `sec_alert` ждёт `send_at`, переживает рестарт, не уходит дважды. */
class BreachAlertRuleTest {
    @get:Rule val tmp = TemporaryFolder()

    private class FakeSender(val online: MutableSet<String>) : PhoneSender {
        val sent = ArrayList<Pair<String, String>>()
        override fun isOnline(pubKeyB64: String) = pubKeyB64 in online
        override fun send(pubKeyB64: String, line: String): SendOutcome {
            sent += pubKeyB64 to line
            return SendOutcome.DELIVERED
        }
    }

    private fun rule(f: BreachFixture, store: DocStore, sender: FakeSender) =
        BreachAlertRule(RuleEngine(store, { f.nowMs }, { }), store, sender, { f.nowMs }, { })

    private fun state(f: BreachFixture) = VJ.str(f.secAlerts().single().data, "state")

    private fun breachHard(f: BreachFixture): String {
        val a = f.enterA()
        f.breach(a, f.req(a, selected = listOf("it_ex")))
        return a
    }

    @Test fun waitsForSendAtThenSendsOnlyToOnlinePhonesAndOnce() {
        val f = BreachFixture()
        breachHard(f)
        val sender = FakeSender(mutableSetOf("sec1"))
        val rule = rule(f, f.store, sender)
        rule.flush()
        assertTrue(sender.sent.isEmpty())              // до send_at (2 мин) ничего
        assertEquals("pending", state(f))
        f.advance(2 * 60_000L + 10)
        rule.flush()
        assertEquals(listOf("sec1"), sender.sent.map { it.first })  // sec2 не в сети
        assertEquals("sent", state(f))
        rule.flush()
        assertEquals(1, sender.sent.size)
    }

    @Test fun survivesBridgeRestart() {
        val path = tmp.root.resolve("b.db").path
        val f = BreachFixture(path)
        breachHard(f)
        f.store.close()
        val store2 = DocStore.open(path) { f.nowMs }
        val sender = FakeSender(mutableSetOf("sec1", "sec2"))
        f.advance(3 * 60_000L)
        rule(f, store2, sender).flush()                // правило нового процесса знает сигнал только из документа
        assertEquals(setOf("sec1", "sec2"), sender.sent.map { it.first }.toSet())
        store2.close()
    }

    @Test fun expiresAfterTtlWithoutSending() {
        val f = BreachFixture()
        breachHard(f)
        val sender = FakeSender(mutableSetOf("sec1"))
        f.advance(31 * 60_000L)
        rule(f, f.store, sender).flush()
        assertTrue(sender.sent.isEmpty())
        assertEquals("expired", state(f))
    }

    @Test fun venueLinkOffHoldsTheSignalUntilItIsBackOn() {
        val f = BreachFixture()
        breachHard(f)
        val g = f.store.get("settings", "global")!!
        f.store.put("settings", "global", g.ver, VJ.with(g.data, "venue_link" to JsonPrimitive(false)))
        val sender = FakeSender(mutableSetOf("sec1"))
        val rule = rule(f, f.store, sender)
        f.advance(5 * 60_000L)
        rule.flush()
        assertTrue(sender.sent.isEmpty())
        assertEquals("pending", state(f))
        val g2 = f.store.get("settings", "global")!!
        f.store.put("settings", "global", g2.ver, VJ.with(g2.data, "venue_link" to JsonPrimitive(true)))
        rule.flush()
        assertEquals(1, sender.sent.size)
    }

    @Test fun nobodyOnlineStillClosesTheSignal() {
        val f = BreachFixture()
        breachHard(f)
        val sender = FakeSender(mutableSetOf())
        f.advance(3 * 60_000L)
        rule(f, f.store, sender).flush()
        assertTrue(sender.sent.isEmpty())
        assertEquals("sent", state(f))
    }

    @Test fun secondSignalForTheSameNodeWithinWindowIsAggregated() {
        val f = BreachFixture()
        val a = breachHard(f)
        val b = f.enterB()
        f.breach(b, f.req(b, selected = listOf("it_b1")))   // тот же узел, другой взломщик
        val sender = FakeSender(mutableSetOf("sec1"))
        f.advance(3 * 60_000L)
        rule(f, f.store, sender).flush()
        assertEquals(2, sender.sent.size)
        assertTrue(sender.sent[0].second != sender.sent[1].second)
        assertTrue(a.isNotEmpty())
    }
}
