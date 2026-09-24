package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.PlayerNotices
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonRewards
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.LootType
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.RamUpgradeStore
import com.megablok10.app.items.OutgoingItem
import com.megablok10.app.items.SendItem
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.shards.ShardStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class CyberdeckState(
    val daemons: List<Daemon> = emptyList(),
    val shards: List<Mb10Qr.Shard> = emptyList(),
    val contacts: ContactsView = ContactsView(),
)

/**
 * Кибердека: коллекция демонов и шардов, скан объектов на площадке (кроме контейнеров — их проверяет BreachViewModel), передача
 * предметов (сценарий SendItem) и расшифровка шардов. Изменения коллекции идут в [work] (скоуп процесса).
 */
class CyberdeckViewModel(
    private val identity: StateFlow<Identity?>,
    private val daemons: DaemonStore,
    private val shards: ShardStore,
    directory: ContactDirectory,
    private val ramUpgrades: RamUpgradeStore,
    private val rewards: DaemonRewards,
    private val sendItem: SendItem,
    private val notices: PlayerNotices,
    private val work: CoroutineScope,
) : ViewModel() {
    val state: StateFlow<CyberdeckState> = combine(daemons.observeAll(), shards.observeAll(), directory.view, ::CyberdeckState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), CyberdeckState())

    private val _segment = MutableStateFlow(SEGMENT_DAEMONS)

    /** Открытый сегмент: [SEGMENT_DAEMONS] или [SEGMENT_SHARDS]. Скан сам переключает на то, что пополнилось. */
    val segment: StateFlow<Int> = _segment.asStateFlow()

    init {
        // Стартовые демоны — у каждого нового персонажа (в том числе после сброса сессии без перезапуска приложения).
        viewModelScope.launch { identity.distinctKey().filterNotNull().collect { work.launch { daemons.ensureSeeded() } } }
    }

    fun selectSegment(segment: Int) { _segment.value = segment }

    /** Отсканированный объект, кроме контейнера: шард, RAM-токен, фрагмент лута от мастера. */
    fun onScan(qr: Mb10Qr) {
        when (qr) {
            is Mb10Qr.Shard -> {
                work.launch { shards.add(qr) }
                _segment.value = SEGMENT_SHARDS
            }
            is Mb10Qr.RamUpgrade -> work.launch {
                val capacity = ramUpgrades.apply(qr)
                notices.show(if (capacity != null) "RAM деки увеличена до $capacity" else "Этот RAM-токен уже был применён")
            }
            is Mb10Qr.LootGrant -> work.launch {
                notices.show(rewards.applyGrant(qr) ?: "Фрагмент повреждён — обратитесь к мастеру")
                _segment.value = if (qr.type == LootType.DAEMON) SEGMENT_DAEMONS else SEGMENT_SHARDS
            }
            else -> notices.show("Этот QR не распознан Кибердекой")
        }
    }

    fun markDecrypted(shardId: String) {
        work.launch { shards.markDecrypted(shardId) }
    }

    /** [label] — как назвать получателя в уведомлении; [onSent] (главный поток) — карточка ушла, можно закрыть предмет. */
    fun transfer(item: OutgoingItem, toPubKeyB64: String, label: String, onSent: () -> Unit) {
        val me = identity.value ?: return
        work.launch {
            if (sendItem(me, item, toPubKeyB64) == null) {
                notices.show("Не удалось передать")
                return@launch
            }
            withContext(Dispatchers.Main) { onSent() }
            notices.show("Передача отправлена: $label")
        }
    }

    companion object {
        const val SEGMENT_DAEMONS = 0
        const val SEGMENT_SHARDS = 1
    }
}
