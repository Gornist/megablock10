package com.megablok10.app.identity

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MeshAutostartTest {
    private val identity = MutableStateFlow<Identity?>(null)
    private val started = mutableListOf<Identity>()

    @Test fun doesNothingWhileThereIsNoCharacter() = runTest {
        backgroundScope.launch { identity.startMeshOncePerCharacter { started += it } }
        runCurrent()

        assertTrue(started.isEmpty())
    }

    @Test fun startsOnceWhenACharacterAppears() = runTest {
        backgroundScope.launch { identity.startMeshOncePerCharacter { started += it } }

        identity.value = Identity("pk-1", "Razor", "Малстром")
        runCurrent()

        assertEquals(listOf("Razor"), started.map { it.callsign })
    }

    @Test fun masterEditsOnTheSameCharacterDoNotRestartTheSession() = runTest {
        backgroundScope.launch { identity.startMeshOncePerCharacter { started += it } }
        identity.value = Identity("pk-1", "Razor", "Малстром")
        runCurrent()

        identity.value = Identity("pk-1", "Blade", "Малстром")   // правка мастера — тот же ключ, другой позывной
        runCurrent()

        assertEquals("сеть не перезапускается на каждую правку", listOf("Razor"), started.map { it.callsign })
    }

    @Test fun sessionResetFollowedByANewCharacterStartsTheSessionAgain() = runTest {
        backgroundScope.launch { identity.startMeshOncePerCharacter { started += it } }
        identity.value = Identity("pk-1", "Razor", "Малстром")
        runCurrent()

        identity.value = null
        identity.value = Identity("pk-2", "Ghost", "Арасака")
        runCurrent()

        assertEquals(listOf("Razor", "Ghost"), started.map { it.callsign })
    }
}
