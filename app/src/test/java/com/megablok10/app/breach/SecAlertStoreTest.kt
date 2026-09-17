package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Правила ревизии v9 §4 — гейтинг и содержимое сигнала СБ, см. SecAlertStore.decide. */
class SecAlertStoreTest {
    private val now = 1_000_000L

    @Test
    fun `breaching your own faction's node never alerts`() {
        val plan = SecAlertStore.decide("Otryad_SB", "Otryad_SB", Tier.NIGHTMARE, BreachOutcome.SUCCESS, emptySet(), now)
        assertNull(plan)
    }

    @Test
    fun `a container with no owner faction never alerts`() {
        val plan = SecAlertStore.decide("", "Zipuny", Tier.NIGHTMARE, BreachOutcome.SUCCESS, emptySet(), now)
        assertNull(plan)
    }

    @Test
    fun `FAIL on a BASE tier node does not alert`() {
        val plan = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.BASE, BreachOutcome.FAIL, emptySet(), now)
        assertNull(plan)
    }

    @Test
    fun `FAIL on a HARD or NIGHTMARE tier node still alerts`() {
        assertTrue(SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.HARD, BreachOutcome.FAIL, emptySet(), now) != null)
        assertTrue(SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.NIGHTMARE, BreachOutcome.FAIL, emptySet(), now) != null)
    }

    @Test
    fun `BLACKOUT among matched effects suppresses the alert entirely regardless of tier or outcome`() {
        val plan = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.NIGHTMARE, BreachOutcome.SUCCESS, setOf(DaemonEffect.BLACKOUT), now)
        assertNull(plan)
    }

    @Test
    fun `TIMESKEW adds 10 minutes on top of the tier's base delay`() {
        val withoutTimeskew = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.HARD, BreachOutcome.SUCCESS, emptySet(), now)!!
        val withTimeskew = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.HARD, BreachOutcome.SUCCESS, setOf(DaemonEffect.TIMESKEW), now)!!
        assertEquals(withoutTimeskew.sendAt + 10 * 60_000L, withTimeskew.sendAt)
    }

    @Test
    fun `NIGHTMARE tier alerts immediately, lower tiers carry a base delay`() {
        val nightmare = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.NIGHTMARE, BreachOutcome.SUCCESS, emptySet(), now)!!
        val hard = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.HARD, BreachOutcome.SUCCESS, emptySet(), now)!!
        assertEquals(now, nightmare.sendAt)
        assertTrue(hard.sendAt > now)
    }

    @Test
    fun `BASE tier still alerts on SUCCESS but never reveals the intruder callsign`() {
        val plan = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.BASE, BreachOutcome.SUCCESS, emptySet(), now)!!
        assertTrue(!plan.revealCallsign)
    }

    @Test
    fun `HARD and NIGHTMARE reveal the callsign unless GHOST matched`() {
        val hard = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.HARD, BreachOutcome.SUCCESS, emptySet(), now)!!
        val nightmare = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.NIGHTMARE, BreachOutcome.SUCCESS, emptySet(), now)!!
        val ghosted = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.NIGHTMARE, BreachOutcome.SUCCESS, setOf(DaemonEffect.GHOST), now)!!
        assertTrue(hard.revealCallsign)
        assertTrue(nightmare.revealCallsign)
        assertTrue(!ghosted.revealCallsign)
    }

    @Test
    fun `only NIGHTMARE reveals a precise timestamp`() {
        val hard = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.HARD, BreachOutcome.SUCCESS, emptySet(), now)!!
        val nightmare = SecAlertStore.decide("Otryad_SB", "Zipuny", Tier.NIGHTMARE, BreachOutcome.SUCCESS, emptySet(), now)!!
        assertTrue(!hard.revealPreciseTime)
        assertTrue(nightmare.revealPreciseTime)
    }
}
