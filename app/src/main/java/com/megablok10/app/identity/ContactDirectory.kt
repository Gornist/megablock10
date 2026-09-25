package com.megablok10.app.identity

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine

/** Контакты игрока и кто из игроков сейчас виден в сети — то, что нужно почти каждому экрану (выбор адресата, «в сети», имена). */
data class ContactsView(
    val contacts: List<Mb10Qr.Contact> = emptyList(),
    val online: List<OnlinePlayer> = emptyList(),
) {
    val onlineKeys: Set<String> = online.mapTo(HashSet()) { it.pubKeyB64 }

    /** Игрок, если он сейчас в сети; null — не в сети. Адреса — только у PeerDirectory. */
    fun peer(pubKeyB64: String): OnlinePlayer? = online.find { it.pubKeyB64 == pubKeyB64 }

    fun contact(pubKeyB64: String): Mb10Qr.Contact? = contacts.find { it.publicKeyB64 == pubKeyB64 }
}

/** Адресная книга: сохранённые контакты ([ContactStore]) вместе с присутствием в сети ([peers] — PeerDirectory.online). */
class ContactDirectory(private val store: ContactStore, private val peers: StateFlow<List<OnlinePlayer>>) {
    val view: Flow<ContactsView> = combine(store.observeAll(), peers, ::ContactsView)

    suspend fun add(contact: Mb10Qr.Contact) = store.add(contact)
}
