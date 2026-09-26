package com.megablok10.app.session

import com.megablok10.app.identity.Identity
import org.junit.Assert.assertEquals
import org.junit.Test

/** Таблица «событие → что запущено» (docs/refactor-plan.md, B3): одно место решает, что работает в фоне. */
class SessionControllerTest {
    private val log = mutableListOf<String>()
    private var foregroundAllowed = true
    private val controller = SessionController(object : SessionActions {
        override fun startMesh(identity: Identity) { log += "mesh+${identity.callsign}" }
        override fun stopMesh() { log += "mesh-" }
        override fun startSync() { log += "sync+" }
        override fun startForeground(): Boolean { log += "fg+"; return foregroundAllowed }
        override fun stopForeground() { log += "fg-" }
    })
    private val razor = Identity("pk-1", "Razor", "Малстром")

    @Test fun processStartWithoutCharacterStartsOnlySync() {
        controller.onProcessStarted()
        controller.onIdentity(null)
        assertEquals(listOf("sync+"), log)
    }

    @Test fun characterAppearingStartsMeshAndForeground() {
        controller.onProcessStarted()
        controller.onIdentity(razor)
        assertEquals(listOf("sync+", "mesh+Razor", "fg+"), log)
    }

    @Test fun masterEditOfTheSameCharacterDoesNotRestartTheMesh() {
        controller.onIdentity(razor)
        controller.onIdentity(razor.copy(callsign = "Blade"))
        assertEquals(listOf("mesh+Razor", "fg+"), log)
    }

    @Test fun anotherKeyRestartsTheMesh() {
        // StateFlow может проглотить промежуточный null (сброс → сразу новый персонаж): смена ключа — тоже перезапуск.
        controller.onIdentity(razor)
        controller.onIdentity(Identity("pk-2", "Ghost", "Арасака"))
        assertEquals(listOf("mesh+Razor", "fg+", "fg-", "mesh-", "mesh+Ghost", "fg+"), log)
    }

    @Test fun sessionResetStopsTheMeshBeforeTheIdentityDisappears() {
        controller.onIdentity(razor)
        log.clear()
        controller.onSessionReset()
        controller.onIdentity(null)
        assertEquals(listOf("fg-", "mesh-"), log)
    }

    @Test fun foregroundRefusedFromBackgroundIsRetriedWhenTheScreenOpens() {
        foregroundAllowed = false
        controller.onProcessStarted()
        controller.onIdentity(razor) // процесс поднят системой без экрана
        foregroundAllowed = true
        controller.onUiStarted()
        controller.onUiStarted() // уже поднят — не дёргаем
        assertEquals(listOf("sync+", "mesh+Razor", "fg+", "fg+"), log)
    }

    @Test fun syncStartsOnceWhoeverAsks() {
        controller.onProcessStarted()
        controller.onUiStarted()
        controller.onProcessStarted()
        assertEquals(listOf("sync+"), log)
    }

    @Test fun screenWithoutCharacterDoesNotStartForeground() {
        controller.onUiStarted()
        assertEquals(listOf("sync+"), log)
    }
}
