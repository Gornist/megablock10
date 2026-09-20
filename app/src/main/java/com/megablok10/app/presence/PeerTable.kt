package com.megablok10.app.presence

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Известный баг платформы на части устройств: NSD может мигнуть onServiceLost сразу за onServiceFound для одного и того же пира без реального разрыва — отсюда дебаунс перед фактическим удалением. 12 с (а не 4): при роуминге между точками Wi-Fi бывают паузы до нескольких секунд, и короткий разрыв не должен выглядеть как «ушёл офлайн» (docs/network-spec.md, §7). */
internal const val LOST_DEBOUNCE_MS = 12_000L

/** После переподключения к сети старые записи NSD недействительны: пиры, не нашедшиеся заново за это время, убираются. */
internal const val REFRESH_GRACE_MS = 15_000L

/**
 * Таблица видимых пиров без единой Android-зависимости (поэтому проверяется JVM-тестами со временем корутин).
 * Ключ — имя NSD-сервиса (его, а не publicKey, возвращает onServiceLost); служебные префиксы: `static:` — отладочные пиры,
 * `srv:` — пиры, подсказанные сервером. Отложенные удаления живут в скоупе из [scopeProvider].
 */
internal class PeerTable(private val scopeProvider: () -> CoroutineScope?) {
    private val peerMap = ConcurrentHashMap<String, PeerInfo>()
    private val pendingRemovals = ConcurrentHashMap<String, Job>()
    private val _peers = MutableStateFlow<List<PeerInfo>>(emptyList())
    val peers: StateFlow<List<PeerInfo>> = _peers.asStateFlow()

    private fun publish() { _peers.value = peerMap.values.toList() }

    fun addStatic(peer: PeerInfo) { peerMap["static:${peer.pubKeyB64}"] = peer; publish() }

    /** Пир найден и разрешён: отменяет отложенное удаление, если оно было запланировано. */
    fun found(serviceName: String, peer: PeerInfo) {
        pendingRemovals.remove(serviceName)?.cancel()
        peerMap[serviceName] = peer
        publish()
    }

    /** NSD сообщил о пропаже: удаляем не сразу, а через [LOST_DEBOUNCE_MS]. */
    fun lost(serviceName: String) {
        scheduleRemoval(serviceName, LOST_DEBOUNCE_MS)
    }

    /** Перезапуск NSD после смены сети: NSD-пиры получают отсрочку [REFRESH_GRACE_MS], статические и серверные остаются как есть. */
    fun graceAll() {
        peerMap.keys.filter { !it.startsWith("static:") && !it.startsWith("srv:") }.forEach { scheduleRemoval(it, REFRESH_GRACE_MS) }
    }

    private fun scheduleRemoval(name: String, afterMs: Long) {
        val scope = scopeProvider() ?: return
        pendingRemovals[name]?.cancel()
        pendingRemovals[name] = scope.launch {
            delay(afterMs)
            peerMap.remove(name)
            pendingRemovals.remove(name)
            publish()
        }
    }

    fun clear() {
        pendingRemovals.values.forEach { it.cancel() }
        pendingRemovals.clear()
        peerMap.clear()
        publish()
    }

    /** Снимок для [restore] после перезапуска NSD. */
    fun snapshot(): Map<String, PeerInfo> = peerMap.toMap()

    fun restore(saved: Map<String, PeerInfo>) { saved.forEach { (k, v) -> peerMap[k] = v }; publish() }

    /** Запасное обнаружение через сервер: пиры, уже найденные NSD, не дублируются; исчезнувшие из списка сервера убираются. */
    fun updateServerPeers(fromServer: List<PeerInfo>, myPubKeyB64: String) {
        val wanted = fromServer.filter { it.pubKeyB64 != myPubKeyB64 && it.port > 0 && it.host.isNotBlank() }.associateBy { "srv:${it.pubKeyB64}" }
        val viaNsdOrStatic = peerMap.filterKeys { !it.startsWith("srv:") }.values.map { it.pubKeyB64 }.toSet()
        var changed = false
        wanted.forEach { (key, peer) ->
            if (peer.pubKeyB64 in viaNsdOrStatic) { if (peerMap.remove(key) != null) changed = true }
            else if (peerMap[key] != peer) { peerMap[key] = peer; changed = true }
        }
        peerMap.keys.filter { it.startsWith("srv:") && it !in wanted }.forEach { peerMap.remove(it); changed = true }
        if (changed) publish()
    }
}
