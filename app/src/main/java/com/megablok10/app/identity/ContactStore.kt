package com.megablok10.app.identity

import com.megablok10.app.data.CharacterDao
import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Известные контакты (отсканированные Character других игроков) поверх Room. */
class ContactStore(private val dao: CharacterDao) {
    fun observeAll(): Flow<List<Mb10Qr.Contact>> =
        dao.observeAll().map { entities ->
            entities.map { Mb10Qr.Contact(it.publicKeyB64, it.callsign, it.faction) }
        }

    suspend fun add(contact: Mb10Qr.Contact) {
        dao.upsert(
            CharacterEntity(
                publicKeyB64 = contact.publicKeyB64,
                callsign = contact.callsign,
                faction = contact.faction
            )
        )
    }
}
