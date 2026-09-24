package com.megablok10.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.PlayerNotices
import com.megablok10.app.identity.CreateCharacter
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.ProvisionResult
import com.megablok10.kit.mesh.PeerInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

/**
 * Состояние корня приложения (AppRoot): есть ли персонаж, выдача по QR мастера, ручное создание, сброс сессии, узлы сети в шапке.
 * Сетевая сессия ([startMesh]) поднимается при появлении персонажа — и после выдачи, и после перезапуска приложения.
 *
 * Выдача, создание и сброс идут в [work] (скоуп процесса), а не в скоупе экрана: их нельзя бросить на полпути, даже если
 * экран за это время сменился или Activity пересоздалась.
 */
class SessionViewModel(
    private val identityStore: IdentityStore,
    val peers: StateFlow<List<PeerInfo>>,
    private val provisioning: suspend (Mb10Qr.Provision) -> ProvisionResult,
    private val create: CreateCharacter,
    private val reset: suspend (Identity?) -> Unit,
    startMesh: (Identity) -> Unit,
    onUiStarted: () -> Unit,
    private val notices: PlayerNotices,
    private val work: CoroutineScope,
) : ViewModel() {
    /** Личность реактивна: создание, сброс и правки мастера (позывной, фракция, RAM) видны сразу. */
    val identity: StateFlow<Identity?> = identityStore.state

    init {
        onUiStarted()
        // Dispatchers.Main, а не immediate: сеть поднимается после первого кадра, а не посреди композиции.
        viewModelScope.launch(Dispatchers.Main) {
            identity.filterNotNull().distinctUntilChangedBy { it.publicKeyB64 }.collect { startMesh(it) }
        }
    }

    fun provision(qr: Mb10Qr.Provision) {
        work.launch {
            val message = when (val result = provisioning(qr)) {
                is ProvisionResult.Applied -> null // личность появилась в IdentityStore.state — экран сменится сам
                ProvisionResult.AlreadyHasIdentity -> "Персонаж уже создан. Повторно — только после сброса сессии в Настройках"
                ProvisionResult.AlreadyUsed -> "Этот код уже использован. Попросите мастера выдать новый"
                is ProvisionResult.Invalid -> result.message
            }
            message?.let(notices::show)
        }
    }

    fun createCharacter(callsign: String, faction: String) {
        work.launch { create(callsign, faction) }
    }

    /** Полный сброс сессии на устройстве (identity/SessionReset): записи о сбросе уходят мастеру до стирания ключа. */
    fun resetSession() {
        work.launch { reset(identityStore.current) }
    }
}
