package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.call.CallControls
import com.megablok10.app.call.CallUiState
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.identity.Identity
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/**
 * Звонки: идущий звонок (плашка поверх любого экрана), журнал и контакты для нового звонка. Разрешение на микрофон спрашивает
 * интерфейс до вызова [start]/[accept] — без него WebRTC не откроет звук.
 */
class CallsViewModel(
    private val calls: CallControls,
    private val identity: StateFlow<Identity?>,
    directory: ContactDirectory,
) : ViewModel() {
    val call: StateFlow<CallUiState> = calls.state
    val log: StateFlow<List<CallLogEntity>> = calls.observeLog().stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), emptyList())
    val contacts: StateFlow<ContactsView> = directory.view.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), ContactsView())

    fun start(peer: OnlinePlayer) { identity.value?.let { calls.startOutgoingCall(it, peer) } }

    fun accept() { identity.value?.let { calls.accept(it) } }

    fun end() { identity.value?.let { calls.endCall(it) } }
}

/** Сколько держать подписку на базу после ухода экрана: поворот и быстрый возврат не перезапускают запросы. */
internal const val STOP_MS = 5_000L
