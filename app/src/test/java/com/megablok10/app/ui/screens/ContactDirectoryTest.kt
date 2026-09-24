package com.megablok10.app.ui.screens

import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.testing.FakeCharacterDao
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ContactDirectoryTest {
    private val bob = TestPlayer("Bob")
    private val eve = TestPlayer("Eve")
    private val dao = FakeCharacterDao(CharacterEntity(bob.key, "Bob", "Арасака"))
    private val peers = MutableStateFlow(listOf(bob.peer, eve.peer))
    private val directory = ContactDirectory(ContactStore(dao), peers)

    @Test fun contactsCarryOnlinePresenceIncludingStrangersInTheNetwork() = runTest {
        val view = directory.view.first()

        assertEquals(listOf(Mb10Qr.Contact(bob.key, "Bob", "Арасака")), view.contacts)
        assertEquals("в сети видны и не-контакты — им пишут по ключу", setOf(bob.key, eve.key), view.onlineKeys)
        assertEquals(bob.peer, view.peer(bob.key))
        assertNull(view.contact(eve.key))
    }

    @Test fun addedContactAppearsAndLeavingTheNetworkIsReflected() = runTest {
        directory.add(Mb10Qr.Contact(eve.key, "Eve", "Малстром"))
        peers.value = listOf(eve.peer)

        val view = directory.view.first()
        assertEquals(listOf("Bob", "Eve"), view.contacts.map { it.callsign })
        assertNull(view.peer(bob.key))
    }
}
