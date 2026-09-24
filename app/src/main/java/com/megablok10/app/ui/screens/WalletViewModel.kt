package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.PlayerNotices
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.identity.Identity
import com.megablok10.app.wallet.PaymentLedger
import com.megablok10.app.wallet.SendPayment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class WalletUiState(
    val balance: Long = 0,
    val transactions: List<TransactionEntity> = emptyList(),
    val contacts: ContactsView = ContactsView(),
)

/**
 * «Финансы»: баланс, операции, перевод игроку (сценарий SendPayment) и отмена недоставленного. Перевод идёт в [work] (скоуп процесса):
 * списание и доставка карточки не должны обрываться, если игрок закрыл форму или ушёл с вкладки.
 */
class WalletViewModel(
    private val identity: StateFlow<Identity?>,
    private val ledger: PaymentLedger,
    directory: ContactDirectory,
    private val sendPayment: SendPayment,
    private val notices: PlayerNotices,
    private val work: CoroutineScope,
) : ViewModel() {
    val state: StateFlow<WalletUiState> = combine(ledger.observeBalance(), ledger.observeAll(), directory.view, ::WalletUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), WalletUiState())

    /** [id] задаёт форма: по нему она показывает статус именно этого перевода. */
    fun send(toPubKeyB64: String, id: String, amount: Long, memo: String) {
        val me = identity.value ?: return
        work.launch {
            // Форма уже проверила сумму, но баланс мог измениться между проверкой и нажатием (другой перевод, правка мастера).
            if (sendPayment(me, toPubKeyB64, amount, memo, id) == null) notices.show("Перевод не прошёл: на балансе не хватает денег")
        }
    }

    fun cancel(id: String) {
        work.launch { ledger.cancelOutgoing(id) }
    }
}
