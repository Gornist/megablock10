package com.megablok10.app.presence

import com.megablok10.app.log.Mb10Log
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val TAG = "PeerTable"

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

    fun addStatic(peer: PeerInfo) { peerMap["static:${peer.pubKeyB64}"] = peer; Mb10Log.event(TAG, "peer.static", "peer" to Mb10Log.short(peer.pubKeyB64), "addr" to "${peer.host}:${peer.port}"); publish() }

    /** Короткое описание для журнала: `ab12cd34(Ник@10.10.0.5:4000,nsd)`. */
    fun describe(): String = peerMap.entries.joinToString(",", "[", "]") { (k, p) ->
        val src = when { k.startsWith("static:") -> "static"; k.startsWith("srv:") -> "srv"; else -> "nsd" }
        "${Mb10Log.short(p.pubKeyB64)}(${p.callsign}@${p.host}:${p.port},$src)"
    }

    /** Пир найден и разрешён: отменяет отложенное удаление, если оно было запланировано. */
    fun found(serviceName: String, peer: PeerInfo) {
        val cancelled = pendingRemovals.remove(serviceName)?.also { it.cancel() } != null
        val isNew = peerMap.put(serviceName, peer) == null
        Mb10Log.event(TAG, "peer.found", "service" to serviceName, "peer" to Mb10Log.short(peer.pubKeyB64), "callsign" to peer.callsign, "addr" to "${peer.host}:${peer.port}", "new" to isNew, "cancelledRemoval" to cancelled)
        publish()
    }

    /** NSD сообщил о пропаже: удаляем не сразу, а через [LOST_DEBOUNCE_MS]. */
    fun lost(serviceName: String) {
        Mb10Log.event(TAG, "peer.lost_reported", "service" to serviceName, "removeInMs" to LOST_DEBOUNCE_MS)
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
            val gone = peerMap.remove(name)
            pendingRemovals.remove(name)
            Mb10Log.event(TAG, "peer.removed", "service" to name, "peer" to Mb10Log.short(gone?.pubKeyB64), "afterMs" to afterMs)
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
        if (changed) {
            Mb10Log.event(TAG, "peer.server_hints", "fromServer" to fromServer.size, "peers" to describe())
            publish()
        }
    }
}
