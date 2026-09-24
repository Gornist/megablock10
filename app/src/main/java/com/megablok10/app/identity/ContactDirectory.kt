package com.megablok10.app.identity

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.mesh.PeerInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine

/** Контакты игрока и кто из игроков сейчас виден в сети — то, что нужно почти каждому экрану (выбор адресата, «в сети», имена). */
data class ContactsView(
    val contacts: List<Mb10Qr.Contact> = emptyList(),
    val online: List<PeerInfo> = emptyList(),
) {
    val onlineKeys: Set<String> = online.mapTo(HashSet()) { it.pubKeyB64 }

    /** Живой адрес игрока; null — сейчас не в сети. */
    fun peer(pubKeyB64: String): PeerInfo? = online.find { it.pubKeyB64 == pubKeyB64 }

    fun contact(pubKeyB64: String): Mb10Qr.Contact? = contacts.find { it.publicKeyB64 == pubKeyB64 }
}

/** Адресная книга: сохранённые контакты ([ContactStore]) вместе с присутствием в сети ([peers] — PresenceService). */
class ContactDirectory(private val store: ContactStore, private val peers: StateFlow<List<PeerInfo>>) {
    val view: Flow<ContactsView> = combine(store.observeAll(), peers, ::ContactsView)

    suspend fun add(contact: Mb10Qr.Contact) = store.add(contact)
}
