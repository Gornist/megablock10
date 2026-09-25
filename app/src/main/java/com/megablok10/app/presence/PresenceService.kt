package com.megablok10.app.presence

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.identity.Identity
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.mesh.PeerTable
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.StateFlow

private const val SERVICE_TYPE = "_mb10chat._tcp."
private const val TAG = "PresenceService"

/**
 * Реклама себя и поиск других устройств этого приложения в локальной сети
 * через NSD (обёртка над mDNS) — без какого-либо центрального сервера, как
 * и весь остальной протокол. host/port живого пира — это адрес его
 * ChatServer, куда отправители (kit LineSocketClient) потом стучатся напрямую.
 *
 * Ключ внутренней карты — имя NSD-сервиса (не publicKey): именно его, а не
 * атрибуты, возвращает onServiceLost, так что только по нему и можно
 * надёжно понять, какая запись пропала.
 */
class PresenceService(private val app: Context, private val wifi: WifiBinder) {
    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var myServiceName: String? = null
    private var scope: CoroutineScope? = null
    private var startArgs: Pair<Identity, Int>? = null

    // Таблица пиров (дебаунс потери, отсрочка после смены сети, серверные подсказки) — чистая логика в kit PeerTable, покрыта JVM-тестами.
    private val table = PeerTable(Mb10Log) { scope }
    val peers: StateFlow<List<PeerInfo>> get() = table.peers

    /** Список видимых пиров одной строкой — для снимка состояния в журнале. */
    fun describePeers(): String = table.describe()

    /**
     * Добавляет пира вручную, минуя NSD — только для прогонов на эмуляторах, где mDNS между
     * устройствами не ходит (см. DebugQrReceiver). В боевом коде не вызывается.
     */
    fun addStaticPeer(peer: PeerInfo) {
        table.addStatic(peer)
    }

    // start/stop/refresh мутируют одни и те же var-поля и могут прийти из разных диспетчеров одновременно
    // (WifiBinder дёргает refresh() из колбэка смены сети, а сессия — start()/stop() из своего потока) — без
    // synchronized(this) это гонка на nsdManager/startArgs и т. п. Монитор реентерабелен: start()
    // вызывает stop() изнутри того же блока, повторный вход тем же потоком безопасен, дедлока не будет.
    fun start(identity: Identity, chatPort: Int): Unit = synchronized(this) {
        stop()
        Mb10Log.event(TAG, "nsd.start", "me" to Mb10Log.short(identity.publicKeyB64), "chatPort" to chatPort, "ip" to wifi.ownIpv4)
        startArgs = identity to chatPort
        val presenceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        scope = presenceScope

        val appContext = app
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
                Mb10Log.event(TAG, "nsd.registered", "service" to info.serviceName)
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Mb10Log.warnEvent(TAG, "nsd.register_failed", "code" to errorCode)
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        registrationListener = regListener
        manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, regListener)

        val discListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) { Mb10Log.event(TAG, "nsd.discovery_started") }
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Mb10Log.warnEvent(TAG, "nsd.discovery_start_failed", "code" to errorCode)
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onServiceFound(info: NsdServiceInfo) {
                if (info.serviceName == myServiceName) return
                Mb10Log.event(TAG, "nsd.service_found", "service" to info.serviceName)
                manager.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        Mb10Log.warnEvent(TAG, "nsd.resolve_failed", "service" to info.serviceName, "code" to errorCode)
                    }
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        val pk = resolved.attributes["pk"]?.toString(Charsets.UTF_8) ?: return
                        if (pk == identity.publicKeyB64) return
                        val cs = resolved.attributes["cs"]?.toString(Charsets.UTF_8) ?: ""
                        val fac = resolved.attributes["fac"]?.toString(Charsets.UTF_8) ?: ""
                        val host = resolved.host?.hostAddress ?: return
                        table.found(resolved.serviceName, PeerInfo(pk, cs, fac, host, resolved.port))
                    }
                })
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                Mb10Log.event(TAG, "nsd.service_lost", "service" to info.serviceName)
                table.lost(info.serviceName)
            }
        }
        discoveryListener = discListener
        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discListener)
    }

    fun stop(): Unit = synchronized(this) {
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

        registrationListener = null
        discoveryListener = null
        multicastLock = null
        nsdManager = null
        myServiceName = null
        scope = null
        table.clear()
    }

    /**
     * Пересоздать NSD-регистрацию и поиск после смены сети (WifiBinder): NSD на Android после переподключения нередко «глохнет» —
     * запись не рекламируется, поиск молчит. Уже известные пиры не сбрасываем сразу (иначе список мигает): они получают отсрочку
     * [REFRESH_GRACE_MS] и остаются, если найдутся заново.
     */
    fun refresh(): Unit = synchronized(this) {
        val args = startArgs ?: return
        Mb10Log.event(TAG, "nsd.refresh", "reason" to "смена сети", "peersBefore" to table.describe())
        // Статические (отладочные) и серверные записи NSD-обновление не касается — они переживают refresh как есть.
        val keep = table.snapshot()
        start(args.first, args.second)
        table.restore(keep)
        table.graceAll()
    }

    /**
     * Запасное обнаружение: сервер знает адреса всех, кто недавно слал heartbeat, и отдаёт их в ответе (docs/network-spec.md, §7 —
     * «запасной путь: известный адрес сервера»). Подсказка — ещё один адрес игрока рядом с найденными NSD; пропавшие из списка сервера убираются.
     */
    fun updateServerPeers(fromServer: List<PeerInfo>, myPubKeyB64: String) = table.updateServerPeers(fromServer, myPubKeyB64)

    /** Исход отправки по адресу пира (LineSocketClient, AppGraph): порядок адресов игрока в [peers] — по нему. */
    fun reportSend(host: String, port: Int, outcome: SendOutcome) = table.reportSend(host, port, outcome)

    private fun deriveServiceName(pubKeyB64: String): String =
        "mb10-" + pubKeyB64.hashCode().toUInt().toString(16)
}
