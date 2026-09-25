package com.megablok10.app.ui.screens

import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * CollectorSettings — настоящий класс, а не фейк: он и так лёгкий (обёртка над SharedPreferences), а MemoryPrefs
 * (см. testing/Fakes.kt) уже используется для него и в других JVM-тестах.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val settings = CollectorSettings(MemoryPrefs(), defaultUrl = "http://default.local")
    private val pendingChanges = MutableStateFlow(0)
    private val peers = MutableStateFlow<List<OnlinePlayer>>(emptyList())
    private var wakeCalls = 0
    private var deviceReportText = "device info"

    private fun vm() = SettingsViewModel(settings, pendingChanges, peers, wakeSync = { wakeCalls++ }, deviceInfo = { deviceReportText })

    @Test fun readsDefaultsWhenNothingIsSavedYet() = runTest {
        val model = vm()

        assertEquals("http://default.local", model.defaultUrl)
        assertEquals("http://default.local", model.collectorUrl())
        assertEquals("", model.gameSecret())
        assertTrue(!model.isProvisioned())
        assertTrue(!model.isProvisionRejected())
    }

    @Test fun savingTheCollectorUrlPersistsItAndWakesSync() = runTest {
        val model = vm()

        model.saveCollectorUrl("http://master.local:8080/")

        assertEquals("http://master.local:8080", model.collectorUrl())
        assertEquals(1, wakeCalls)
    }

    @Test fun savingAnEmptyGameSecretClearsIt() = runTest {
        val model = vm()
        model.saveGameSecret("code-1")
        assertEquals("code-1", model.gameSecret())

        model.saveGameSecret("")

        assertEquals("", model.gameSecret())
        assertEquals(2, wakeCalls)
    }

    @Test fun pendingChangesAndPeersFollowTheInjectedFlows() = runTest {
        val model = vm()
        backgroundScope.launch { model.pendingChanges.collect {} }
        runCurrent()

        pendingChanges.value = 3
        peers.value = listOf(OnlinePlayer("pk", "Bob", "Арасака"))
        runCurrent()

        assertEquals(3, model.pendingChanges.value)
        assertEquals(listOf("Bob"), model.peers.value.map { it.callsign })
    }

    @Test fun deviceReportComesFromTheInjectedPort() = runTest {
        deviceReportText = "Pixel 5, Android 13"
        val model = vm()

        assertEquals("Pixel 5, Android 13", model.deviceReport())
    }
}
