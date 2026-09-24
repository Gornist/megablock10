package com.megablok10.app.breach

import androidx.lifecycle.ViewModel
import com.megablok10.app.identity.Identity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Взлом контейнера: проверка перед взломом (сценарий CheckBreachAccess) и итог взлома (FinishBreach). Открытый контейнер живёт здесь,
 * а не в экране — не теряется при переключении вкладок. Один экземпляр на персонажа (ключ ViewModel — ключ личности): после
 * сброса сессии новый персонаж не унаследует открытый контейнер прежнего.
 *
 * Проверка и итог идут в [work] (скоуп процесса): запись отказа, награда и сигнал СБ не должны обрываться, если игрок нажал
 * «Новый контейнер» или ушёл с экрана, пока они записываются.
 */
class BreachViewModel(
    private val identity: StateFlow<Identity?>,
    private val checkAccess: CheckBreachAccess,
    private val finishBreach: FinishBreach,
    private val work: CoroutineScope,
) : ViewModel() {
    private val _container = MutableStateFlow<Container?>(null)
    private val _issue = MutableStateFlow<BreachAccess.Blocked?>(null)

    /** Контейнер, к которому открыт взлом (проверка пройдена); null — обычный экран Кибердеки. */
    val container: StateFlow<Container?> = _container.asStateFlow()

    /** Почему последний отсканированный контейнер не открылся; null — нечего показывать. */
    val issue: StateFlow<BreachAccess.Blocked?> = _issue.asStateFlow()

    fun open(container: Container) {
        val me = identity.value ?: return
        _issue.value = null
        work.launch {
            when (val access = checkAccess(me, container)) {
                BreachAccess.Open -> _container.value = container
                is BreachAccess.Blocked -> _issue.value = access
            }
        }
    }

    fun dismissIssue() { _issue.value = null }

    fun close() { _container.value = null }

    /** [onDone] получает награду на главном потоке — экран показывает её в итогах взлома. */
    fun finish(container: Container, result: BreachResult, seed: Long, onDone: (RewardOutcome) -> Unit) {
        val me = identity.value ?: return
        work.launch {
            val outcome = finishBreach(me, container, result, seed)
            withContext(Dispatchers.Main) { onDone(outcome) }
        }
    }
}
