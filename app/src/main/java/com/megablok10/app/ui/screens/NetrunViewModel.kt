package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import com.megablok10.app.breach.Daemon
import com.megablok10.app.identity.Identity
import com.megablok10.app.netrun.NetrunEntry
import com.megablok10.app.netrun.NetrunEntryState
import com.megablok10.app.qr.Mb10Qr
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Вход в «Сеть» из Кибердеки: отсканированная стойка открывает выбор деки, подтверждение запускает сценарий [NetrunEntry]. Сдача
 * идёт в [work] (скоуп процесса): карточки и запрос нельзя бросить на полпути, если игрок ушёл с экрана.
 */
class NetrunViewModel(
    private val identity: StateFlow<Identity?>,
    private val entry: NetrunEntry,
    private val work: CoroutineScope,
) : ViewModel() {
    private val _rack = MutableStateFlow<Mb10Qr.Rack?>(null)

    /** Стойка, для которой открыт выбор деки; null — выбор закрыт. */
    val rack: StateFlow<Mb10Qr.Rack?> = _rack.asStateFlow()

    /** Ход входа (отправка, ожидание ответа Моста, итог). */
    val entryState: StateFlow<NetrunEntryState> = entry.state

    fun openRack(rack: Mb10Qr.Rack) {
        entry.onRackScanned(rack)
        _rack.value = rack
    }

    fun closePicker() { _rack.value = null }

    /** Сдать [daemons]; [protectedId] — демон защищённого слота. */
    fun enter(daemons: List<Daemon>, protectedId: String) {
        val me = identity.value ?: return
        val rack = _rack.value ?: return
        _rack.value = null
        work.launch { entry.enter(me, rack, daemons, protectedId) }
    }

    fun retry() = entry.retry()

    fun dismiss() = entry.dismiss()
}
