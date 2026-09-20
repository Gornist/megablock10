package com.megablok10.app.presence

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.util.Log
import com.megablok10.app.identity.Identity
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val SERVICE_TYPE = "_mb10chat._tcp."
private const val TAG = "PresenceService"

/** Известный баг платформы на части устройств: NSD может мигнуть onServiceLost сразу за onServiceFound для одного и того же пира без реального разрыва — отсюда дебаунс перед фактическим удалением. 12 с (а не 4): при роуминге между точками Wi-Fi бывают паузы до нескольких секунд, и короткий разрыв не должен выглядеть как «ушёл офлайн» (docs/network-spec.md, §7). */
private const val LOST_DEBOUNCE_MS = 12_000L

/** После переподключения к сети старые записи NSD недействительны: пиры, не нашедшиеся заново за это время, убираются. */
private const val REFRESH_GRACE_MS = 15_000L

/**
 * Реклама себя и поиск других устройств этого приложения в локальной сети
 * через NSD (обёртка над mDNS) — без какого-либо центрального сервера, как
 * и весь остальной протокол. host/port живого пира — это адрес его
 * ChatServer, куда ChatClient потом стучится напрямую.
 *
 * Ключ внутренней карты — имя NSD-сервиса (не publicKey): именно его, а не
 * атрибуты, возвращает onServiceLost, так что только по нему и можно
 * надёжно понять, какая запись пропала.
 */
object PresenceService {
    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var myServiceName: String? = null
    private var scope: CoroutineScope? = null
    private var startArgs: Triple<Context, Identity, Int>? = null

    // Источник правды — потокобезопасная карта (колбэки NSD приходят не из главного потока);
    // _peers лишь публикует её снимок при каждом изменении.
    private val peerMap = ConcurrentHashMap<String, PeerInfo>()
    // Отложенные удаления по onServiceLost — ключ тот же serviceName, что и у peerMap.
    // Если до срабатывания придёт onServiceFound на того же пира, job отменяется и
    // пир не пропадает из списка вовсе — то самое мерцание, которого не должно быть видно.
    private val pendingRemovals = ConcurrentHashMap<String, Job>()
    private val _peers = MutableStateFlow<List<PeerInfo>>(emptyList())
    val peers: StateFlow<List<PeerInfo>> = _peers.asStateFlow()

    private fun publishPeers() {
        _peers.value = peerMap.values.toList()
    }

    /**
     * Добавляет пира вручную, минуя NSD — только для прогонов на эмуляторах, где mDNS между
     * устройствами не ходит (см. DebugQrReceiver). В боевом коде не вызывается.
     */
    fun addStaticPeer(peer: PeerInfo) {
        peerMap["static:${peer.pubKeyB64}"] = peer
        publishPeers()
    }

    fun start(context: Context, identity: Identity, chatPort: Int) {
        stop()
        startArgs = Triple(context.applicationContext, identity, chatPort)
        val presenceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        scope = presenceScope

        val appContext = context.applicationContext
        val wifiManager = appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifiManager?.createMulticastLock("mb10-presence")?.apply {
            setReferenceCounted(true)
            acquire()
        }

        val manager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsdManager = manager

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = deriveServiceName(identity.publicKeyB64)
            serviceType = SERVICE_TYPE
            port = chatPort
            setAttribute("pk", identity.publicKeyB64)
            setAttribute("cs", identity.callsign)
            setAttribute("fac", identity.faction)
        }

        val regListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                myServiceName = info.serviceName
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "Регистрация NSD не удалась: $errorCode")
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        registrationListener = regListener
        manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, regListener)

        val discListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "Поиск NSD не удалось запустить: $errorCode")
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onServiceFound(info: NsdServiceInfo) {
                if (info.serviceName == myServiceName) return
                manager.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        Log.w(TAG, "Не удалось разрешить пира ${info.serviceName}: $errorCode")
                    }
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        val pk = resolved.attributes["pk"]?.toString(Charsets.UTF_8) ?: return
                        if (pk == identity.publicKeyB64) return
                        val cs = resolved.attributes["cs"]?.toString(Charsets.UTF_8) ?: ""
                        val fac = resolved.attributes["fac"]?.toString(Charsets.UTF_8) ?: ""
                        val host = resolved.host?.hostAddress ?: return
                        // Пир снова нашёлся — отменяем его отложенное удаление, если оно было запланировано.
                        pendingRemovals.remove(resolved.serviceName)?.cancel()
                        peerMap[resolved.serviceName] = PeerInfo(pk, cs, fac, host, resolved.port)
                        publishPeers()
                    }
                })
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                val name = info.serviceName
                pendingRemovals[name]?.cancel()
                pendingRemovals[name] = presenceScope.launch {
                    delay(LOST_DEBOUNCE_MS)
                    peerMap.remove(name)
                    pendingRemovals.remove(name)
                    publishPeers()
                }
            }
        }
        discoveryListener = discListener
        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discListener)
    }

    fun stop() {
        startArgs = null
        val manager = nsdManager
        try {
            registrationListener?.let { manager?.unregisterService(it) }
        } catch (e: Exception) { /* уже не зарегистрирован — не страшно */ }
        try {
            discoveryListener?.let { manager?.stopServiceDiscovery(it) }
        } catch (e: Exception) { /* поиск уже не шёл — не страшно */ }
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
        } catch (e: Exception) { /* ignore */ }

        scope?.cancel()
        pendingRemovals.clear()

        registrationListener = null
        discoveryListener = null
        multicastLock = null
        nsdManager = null
        myServiceName = null
        scope = null
        peerMap.clear()
        publishPeers()
    }

    /**
     * Пересоздать NSD-регистрацию и поиск после смены сети (WifiBinder): NSD на Android после переподключения нередко «глохнет» —
     * запись не рекламируется, поиск молчит. Уже известные пиры не сбрасываем сразу (иначе список мигает): они получают отсрочку
     * [REFRESH_GRACE_MS] и остаются, если найдутся заново.
     */
    fun refresh() {
        val args = startArgs ?: return
        // Статические (отладочные) и серверные записи NSD-обновление не касается — они переживают refresh как есть.
        val keep = peerMap.toMap()
        start(args.first, args.second, args.third)
        val presenceScope = scope ?: return
        keep.forEach { (name, peer) ->
            peerMap[name] = peer
            if (name.startsWith("static:") || name.startsWith("srv:")) return@forEach
            pendingRemovals[name] = presenceScope.launch {
                delay(REFRESH_GRACE_MS)
                peerMap.remove(name)
                pendingRemovals.remove(name)
                publishPeers()
            }
        }
        publishPeers()
    }

    /**
     * Запасное обнаружение: сервер знает адреса всех, кто недавно слал heartbeat, и отдаёт их в ответе (docs/network-spec.md, §7 —
     * «запасной путь: известный адрес сервера»). Пиры, которых NSD уже нашёл сам, не дублируются; пропавшие из списка сервера убираются.
     */
    fun updateServerPeers(fromServer: List<PeerInfo>, myPubKeyB64: String) {
        val wanted = fromServer.filter { it.pubKeyB64 != myPubKeyB64 && it.port > 0 && it.host.isNotBlank() }.associateBy { "srv:${it.pubKeyB64}" }
        val viaNsdOrStatic = peerMap.filterKeys { !it.startsWith("srv:") }.values.map { it.pubKeyB64 }.toSet()
        var changed = false
        wanted.forEach { (key, peer) ->
            if (peer.pubKeyB64 in viaNsdOrStatic) { if (peerMap.remove(key) != null) changed = true }
            else if (peerMap[key] != peer) { peerMap[key] = peer; changed = true }
        }
        peerMap.keys.filter { it.startsWith("srv:") && it !in wanted }.forEach { peerMap.remove(it); changed = true }
        if (changed) publishPeers()
    }

    private fun deriveServiceName(pubKeyB64: String): String =
        "mb10-" + pubKeyB64.hashCode().toUInt().toString(16)
}
