package com.megablok10.app.identity

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.app.testing.RecordedChanges
import com.megablok10.kit.sync.ChangeRecorder
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CreateCharacterTest {
    private val prefs = MemoryPrefs()
    private val identity = IdentityStore(prefs)
    private val queue = RecordedChanges(null)
    // Подписывает сам IdentityStore — как в приложении: ключ появляется в момент создания.
    private val changes = ChangeRecorder(queue, { identity.recordSigner() })

    @Test fun newCharacterGetsKeysAndIsAnnouncedToTheMaster() = runTest {
        val created = CreateCharacter(identity, changes)("RAZOR", "Малстром")

        assertEquals(created, identity.state.value)
        assertEquals(listOf(ChangeField.CALLSIGN to "RAZOR", ChangeField.FACTION to "Малстром"), queue.rows.map { it.field to it.newValue })
        assertTrue(queue.rows.all { it.reason == ChangeReason.CHARACTER_CREATED && it.oldValue == null && it.subjectKeyB64 == created.publicKeyB64 })
    }

    @Test fun existingCharacterIsReturnedAsIsWithoutRecords() = runTest {
        val first = CreateCharacter(identity, changes)("RAZOR", "Малстром")
        queue.rows.clear()

        val again = CreateCharacter(identity, changes)("GHOST", "Арасака")

        assertEquals(first, again)
        assertTrue(queue.rows.isEmpty())
    }
}
