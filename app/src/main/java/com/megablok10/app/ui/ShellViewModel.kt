package com.megablok10.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.identity.Identity
import com.megablok10.app.ui.nav.AppTab
import com.megablok10.app.ui.screens.STOP_MS
import com.megablok10.app.ui.screens.distinctKey
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn

/**
 * Оболочка приложения (шапка и нижнее меню): баланс в шапке и бейджи вкладок «Чат»/«Звонки». Вкладка, на которую
 * переключились, сама гасит свой бейдж ([onTabShown]) — отдельного экрана «прочитано» нет.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShellViewModel(
    identity: StateFlow<Identity?>,
    balance: Flow<Long>,
    unreadChatThreads: (myPubKeyB64: String) -> Flow<Int>,
    missedCalls: Flow<Int>,
    private val markChatSeen: () -> Unit,
    private val markCallsSeen: () -> Unit,
) : ViewModel() {
    val balance: StateFlow<Long> = balance.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), 0L)

    val unreadChat: StateFlow<Int> = identity.distinctKey()
        .flatMapLatest { key -> if (key == null) flowOf(0) else unreadChatThreads(key) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), 0)

    val missedCalls: StateFlow<Int> = missedCalls.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), 0)

    fun onTabShown(tab: AppTab) {
        when (tab) {
            AppTab.Chat -> markChatSeen()
            AppTab.Calls -> markCallsSeen()
            else -> {}
        }
    }
}
