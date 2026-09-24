package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Профиль: свои контакты (кто в сети — для звонка и сообщения) и добавление нового по QR. */
class ContactsViewModel(private val directory: ContactDirectory, private val work: CoroutineScope) : ViewModel() {
    val contacts: StateFlow<ContactsView> = directory.view.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), ContactsView())

    fun add(contact: Mb10Qr.Contact) {
        work.launch { directory.add(contact) }
    }
}
