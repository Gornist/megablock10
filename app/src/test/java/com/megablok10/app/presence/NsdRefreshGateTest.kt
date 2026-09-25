package com.megablok10.app.presence

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Когда пересоздавать NSD: только при настоящей смене сети — лишнее пересоздание теряет незавершённую регистрацию (e2e A4, wifi-bind). */
class NsdRefreshGateTest {
    @Test fun processStartBeforeWifiBindingDoesNotRestartNsd() {
        // Журнал CI: nsd.start без ip → wifi.available (привязка, ip=10.0.2.16) → wifi.link_changed с тем же ip.
        val gate = NsdRefreshGate<Int>().apply { started(null, null) }
        assertFalse("первая привязка — запомнить", gate.shouldRefresh(100, "10.0.2.16"))
        assertFalse("link_changed с тем же ip", gate.shouldRefresh(100, "10.0.2.16"))
    }

    @Test fun sameNetworkAndIpIsNotAChange() {
        val gate = NsdRefreshGate<Int>().apply { started(100, "10.0.2.16") }
        assertFalse(gate.shouldRefresh(100, "10.0.2.16"))
    }

    @Test fun reconnectRestartsNsdBothOnLossAndOnNewNetwork() {
        val gate = NsdRefreshGate<Int>().apply { started(100, "10.0.2.17") }
        assertTrue("wifi.lost", gate.shouldRefresh(null, null))
        assertTrue("после потери — новая сеть: это не первая привязка", gate.shouldRefresh(102, "10.0.2.17"))
        assertFalse("link_changed вслед", gate.shouldRefresh(102, "10.0.2.17"))
    }

    @Test fun ipChangeOnTheSameNetworkRestartsNsd() {
        val gate = NsdRefreshGate<Int>().apply { started(100, "10.10.0.5") }
        assertTrue(gate.shouldRefresh(100, "10.10.0.9"))
    }

    @Test fun onlyTheFirstBindingAfterStartIsAdopted() {
        val gate = NsdRefreshGate<Int>().apply { started(null, null) }
        assertFalse(gate.shouldRefresh(100, "10.0.2.16"))
        assertTrue(gate.shouldRefresh(null, null))
        assertTrue(gate.shouldRefresh(101, "10.0.2.16"))
    }
}
