package com.megablok10.app.identity

import android.content.Context
import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Известные контакты (отсканированные Character других игроков) поверх Room. */
object ContactStore {
    fun observeAll(context: Context): Flow<List<Mb10Qr.Contact>> =
        Mb10Database.get(context).characterDao().observeAll().map { entities ->
            entities.map { Mb10Qr.Contact(it.publicKeyB64, it.callsign, it.faction) }
        }

    suspend fun add(context: Context, contact: Mb10Qr.Contact) {
        Mb10Database.get(context).characterDao().upsert(
            CharacterEntity(
                publicKeyB64 = contact.publicKeyB64,
                callsign = contact.callsign,
                faction = contact.faction
            )
        )
    }
}
