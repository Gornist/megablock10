package com.megablok10.app.ui.screens

import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.log.LogStore
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File

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

    private class FakeLogStore : LogStore {
        var bytes = 0L
        var clears = 0
        var flushes = 0
        var exportedWith: String? = null
        var zip: File? = null
        override fun sizeBytes() = bytes
        override fun clear() { clears++; bytes = 0 }
        override fun flush() { flushes++ }
        override fun exportZip(deviceInfo: String): File? { exportedWith = deviceInfo; return zip ?: error("нет журнала") }
    }

    private val logStore = FakeLogStore()

    private fun vm() = SettingsViewModel(settings, pendingChanges, peers, wakeSync = { wakeCalls++ }, deviceInfo = { deviceReportText }, logStore = logStore)

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

    @Test fun logSizeStartsFromTheStoreInKilobytes() = runTest {
        logStore.bytes = 5 * 1024 + 100

        assertEquals(5L, vm().logSizeKb.value)
    }

    @Test fun markLogIgnoresBlankText() = runTest {
        val model = vm()

        assertTrue(!model.markLog("   "))

        assertNull(model.logStatus.value)
        assertEquals(0, logStore.flushes)
    }

    @Test fun markLogReportsAndRefreshesTheSize() = runTest {
        val model = vm()
        logStore.bytes = 3 * 1024

        assertTrue(model.markLog(" проверка "))

        assertEquals("Метка записана", model.logStatus.value)
        assertEquals(1, logStore.flushes)
        assertEquals(3L, model.logSizeKb.value)
    }

    @Test fun clearLogClearsTheStoreAndReportsIt() = runTest {
        logStore.bytes = 9 * 1024
        val model = vm()

        model.clearLog()

        assertEquals(1, logStore.clears)
        assertEquals(0L, model.logSizeKb.value)
        assertEquals("Журнал очищен", model.logStatus.value)
    }

    @Test fun exportLogPassesTheDeviceReportAndReportsTheArchiveSize() = runTest {
        deviceReportText = "Pixel 5"
        logStore.zip = File.createTempFile("mb10-test", ".zip").apply { writeBytes(ByteArray(2048)); deleteOnExit() }
        val model = vm()

        val zip = model.exportLog()

        assertEquals(logStore.zip, zip)
        assertEquals("Pixel 5", logStore.exportedWith)
        assertEquals("Архив: 2 КБ", model.logStatus.value)
    }

    @Test fun exportLogReportsAFailureWhenTheArchiveCannotBeBuilt() = runTest {
        val model = vm()

        assertNull(model.exportLog())

        assertEquals("Не удалось собрать архив", model.logStatus.value)
    }

    @Test fun reopeningTheScreenRereadsTheSizeAndDropsTheOldStatus() = runTest {
        val model = vm()
        model.markLog("метка")
        logStore.bytes = 7 * 1024

        model.onLogScreenShown()

        assertEquals(7L, model.logSizeKb.value)
        assertNull(model.logStatus.value)
    }
}
