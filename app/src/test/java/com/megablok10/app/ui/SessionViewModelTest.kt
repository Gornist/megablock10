package com.megablok10.app.ui

import com.megablok10.app.identity.CreateCharacter
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.ProvisionResult
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.app.testing.RecordedChanges
import com.megablok10.app.testing.RecordingNotices
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import com.megablok10.kit.sync.ChangeRecorder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SessionViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val identity = IdentityStore(MemoryPrefs())
    private val queue = RecordedChanges(null)
    // Подписывает сам IdentityStore — как в приложении: ключ появляется в момент создания персонажа.
    private val changes = ChangeRecorder(queue, { identity.recordSigner() })
    private val notices = RecordingNotices()
    private var uiStarts = 0
    private var provisionResult: ProvisionResult = ProvisionResult.AlreadyUsed
    private val resets = mutableListOf<Identity?>()

    private fun TestScope.session(work: CoroutineScope = this) = SessionViewModel(
        identityStore = identity,
        peers = MutableStateFlow(emptyList()),
        provisioning = { provisionResult },
        create = CreateCharacter(identity, changes),
        reset = { resets += it; identity.clear() },
        onUiStarted = { uiStarts++ },
        notices = notices,
        work = work,
    )

    @Test fun uiStartedFiresOnceAndResetGetsTheIdentityBeforeItIsWiped() = runTest {
        val vm = session()
        assertEquals(1, uiStarts)

        vm.createCharacter("RAZOR", "Малстром")
        runCurrent()
        identity.applyCallsignOverride("BLADE")   // правка мастера — та же личность, тот же persistent-ключ
        vm.resetSession()
        runCurrent()

        assertEquals("сброс получил личность до стирания", "BLADE", resets.single()?.callsign)
        assertEquals(1, uiStarts)
    }

    @Test fun provisioningProblemsAreExplainedToThePlayer() = runTest {
        val vm = session()
        val qr = Mb10Qr.Provision("p-1", collectorUrl = "", gameSecret = "", callsign = "RAZOR", faction = "Малстром", startBalance = 100, ramCapacity = 0)

        for (result in listOf(
            ProvisionResult.AlreadyHasIdentity,
            ProvisionResult.AlreadyUsed,
            ProvisionResult.Invalid("QR повреждён"),
            ProvisionResult.Applied(Identity("k", "RAZOR", "Малстром")),
        )) {
            provisionResult = result
            vm.provision(qr)
            runCurrent()
        }

        assertEquals(
            listOf(
                "Персонаж уже создан. Повторно — только после сброса сессии в Настройках",
                "Этот код уже использован. Попросите мастера выдать новый",
                "QR повреждён",
            ),
            notices.shown,
        )
    }

    @Test fun characterCreationRunsInTheProcessScopeNotTheScreens() = runTest {
        val work = TestScope(testScheduler)
        val vm = session(work)

        vm.createCharacter("RAZOR", "Малстром")
        assertNull("ещё не выполнено: ждёт скоуп процесса", vm.identity.value)
        work.testScheduler.advanceUntilIdle()

        assertEquals("RAZOR", vm.identity.value?.callsign)
        assertEquals(2, queue.rows.size)
        assertNull("записи создания подписаны уже новым ключом", queue.rows.firstOrNull { it.subjectKeyB64 != vm.identity.value?.publicKeyB64 })
    }
}
