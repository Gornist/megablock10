package com.megablok10.app.presence

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.mesh.PeerTable
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

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
 *
 * Операции NsdManager асинхронны (ответ — колбэком через сотни миллисекунд) и не терпят суеты: снятая до ответа регистрация
 * терялась, и устройство переставало быть видно (e2e A4, wifi-bind 25.09). Поэтому регистрация и поиск — [NsdSlot]
 * («желаемое → фактическое», операции строго по одной), разрешение найденных — [NsdResolveQueue] (по одному: на Android до 14
 * одновременные падают с FAILURE_ALREADY_ACTIVE). Логика обеих — чистая, под JVM-тестами; здесь — только вызовы Android.
 */
class PresenceService(private val app: Context, private val wifi: WifiBinder) {
    private val manager: NsdManager? by lazy { app.getSystemService(Context.NSD_SERVICE) as? NsdManager }

    /** Таймеры операций NSD — живут с процессом, не с сессией: ответ на операцию может прийти уже после stop(). */
    private val opsScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val scheduler = NsdScheduler { ms, block ->
        val job = opsScope.launch { delay(ms); block() }
        return@NsdScheduler { job.cancel() }
    }

    /** Скоуп отложенных удалений пиров (PeerTable) — пока присутствие запущено. */
    @Volatile private var scope: CoroutineScope? = null
    @Volatile private var identity: Identity? = null
    @Volatile private var myServiceName: String? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val refreshGate = NsdRefreshGate<Any>()

    // Таблица пиров (дебаунс потери, отсрочка после смены сети, серверные подсказки) — чистая логика в kit PeerTable, покрыта JVM-тестами.
    private val table = PeerTable(Mb10Log) { scope }
    val peers: StateFlow<List<PeerInfo>> get() = table.peers
    val players: StateFlow<List<OnlinePlayer>> get() = table.players

    private data class Registration(val identity: Identity, val port: Int)

    /** Слушатель операции Android со своим номером остановки: запоздалый ответ старого слушателя не засчитается новой операции. */
    private class Stoppable<L>(val listener: L) { @Volatile var stopToken = 0 }

    // Меняются только внутри операций своего слота (под его монитором).
    @Volatile private var activeRegistration: Stoppable<NsdManager.RegistrationListener>? = null
    @Volatile private var activeDiscovery: Stoppable<NsdManager.DiscoveryListener>? = null

    private val registration: NsdSlot<Registration> = NsdSlot(object : NsdSlot.Ops<Registration> {
        override fun start(value: Registration, token: Int) = register(value, token)
        override fun stop(token: Int) = unregister(token)
    }, scheduler, onEvent = { Mb10Log.warnEvent(TAG, "nsd.register_$it") })

    private val discovery: NsdSlot<Identity> = NsdSlot(object : NsdSlot.Ops<Identity> {
        override fun start(value: Identity, token: Int) = discover(value, token)
        override fun stop(token: Int) = stopDiscovery(token)
    }, scheduler, onEvent = { Mb10Log.warnEvent(TAG, "nsd.discovery_$it") })

    private val resolves = NsdResolveQueue<NsdServiceInfo>({ it.serviceName }, ::resolve, scheduler)

    /** Список видимых пиров одной строкой — для снимка состояния в журнале. */
    fun describePeers(): String = table.describe()

    /**
     * Добавляет пира вручную, минуя NSD — только для прогонов на эмуляторах, где mDNS между
     * устройствами не ходит (см. DebugQrReceiver). В боевом коде не вызывается.
     */
    fun addStaticPeer(peer: PeerInfo) {
        table.addStatic(peer)
    }

    /** Объявить себя (порт [chatPort] сервера строк) и искать других. Повтор с теми же данными — не операция (NsdSlot). */
    fun start(identity: Identity, chatPort: Int): Unit = synchronized(this) {
        Mb10Log.event(TAG, "nsd.start", "me" to Mb10Log.short(identity.publicKeyB64), "chatPort" to chatPort, "ip" to wifi.ownIpv4)
        refreshGate.started(wifi.boundNetwork, wifi.ownIpv4)
        this.identity = identity
        if (scope == null) scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        if (multicastLock == null) {
            val wifiManager = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("mb10-presence")?.apply { setReferenceCounted(true); acquire() }
        }
        registration.want(Registration(identity, chatPort))
        discovery.want(identity)
    }

    fun stop(): Unit = synchronized(this) {
        registration.want(null)
        discovery.want(null)
        resolves.clear()
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) { /* уже отпущен — не страшно */ }
        multicastLock = null
        scope?.cancel()
        scope = null
        identity = null
        table.clear()
    }

    /**
     * Пересоздать NSD-регистрацию и поиск после смены сети (WifiBinder): NSD на Android после переподключения нередко «глохнет» —
     * запись не рекламируется, поиск молчит. Уже известные пиры не сбрасываем сразу (иначе список мигает): они получают отсрочку
     * [com.megablok10.kit.mesh.REFRESH_GRACE_MS] и остаются, если найдутся заново. Пересоздание идёт по очереди с идущими
     * операциями (NsdSlot.restart), незавершённая регистрация не снимается. true — сеть действительно сменилась.
     */
    fun refresh(): Boolean = synchronized(this) {
        if (identity == null) return false
        // Та же сеть и тот же IP (link_changed вслед за available) или первая привязка после запуска — не трогаем регистрацию (NsdRefreshGate).
        if (!refreshGate.shouldRefresh(wifi.boundNetwork, wifi.ownIpv4)) {
            Mb10Log.event(TAG, "nsd.refresh_skipped", "network" to wifi.boundNetwork, "ip" to wifi.ownIpv4, "registered" to (myServiceName != null))
            return false
        }
        Mb10Log.event(TAG, "nsd.refresh", "reason" to "смена сети", "peersBefore" to table.describe())
        table.graceAll()
        registration.restart()
        discovery.restart()
        true
    }

    /**
     * Запасное обнаружение: сервер знает адреса всех, кто недавно слал heartbeat, и отдаёт их в ответе (docs/network-spec.md, §7 —
     * «запасной путь: известный адрес сервера»). Подсказка — ещё один адрес игрока рядом с найденными NSD; пропавшие из списка сервера убираются.
     */
    fun updateServerPeers(fromServer: List<PeerInfo>, myPubKeyB64: String) = table.updateServerPeers(fromServer, myPubKeyB64)

    /** Исход отправки по адресу пира (LineSocketClient, AppGraph): порядок адресов игрока в [peers] — по нему; [answeredBy] — чей ключ ответил. */
    fun reportSend(host: String, port: Int, outcome: SendOutcome, answeredBy: String?) = table.reportSend(host, port, outcome, answeredBy)

    /** Игрок сам прислал строку в конверте с этого адреса (ChatServer): где он слушает — свежее любого обнаружения. */
    fun heard(pubKeyB64: String, host: String, port: Int) = table.heard(pubKeyB64, host, port)

    // --- операции Android: только вызов и колбэк в слот/очередь ---

    private fun register(value: Registration, token: Int) {
        val m = manager ?: return registration.onStartFailed(token)
        val info = NsdServiceInfo().apply {
            serviceName = deriveServiceName(value.identity.publicKeyB64)
            serviceType = SERVICE_TYPE
            port = value.port
            setAttribute("pk", value.identity.publicKeyB64)
            setAttribute("cs", value.identity.callsign)
            setAttribute("fac", value.identity.faction)
        }
        lateinit var holder: Stoppable<NsdManager.RegistrationListener>
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                myServiceName = info.serviceName
                Mb10Log.event(TAG, "nsd.registered", "service" to info.serviceName, "port" to value.port)
                registration.onStarted(token)
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Mb10Log.warnEvent(TAG, "nsd.register_failed", "code" to errorCode)
                registration.onStartFailed(token)
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) {
                Mb10Log.event(TAG, "nsd.unregistered", "service" to info.serviceName)
                registration.onStopped(holder.stopToken)
            }
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Mb10Log.warnEvent(TAG, "nsd.unregister_failed", "code" to errorCode)
                registration.onStopped(holder.stopToken)
            }
        }
        holder = Stoppable(listener)
        activeRegistration = holder
        try {
            m.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            Mb10Log.warnEvent(TAG, "nsd.register_failed", "error" to e.javaClass.simpleName)
            activeRegistration = null
            registration.onStartFailed(token)
        }
    }

    private fun unregister(token: Int) {
        val holder = activeRegistration
        activeRegistration = null
        myServiceName = null
        if (holder == null) return registration.onStopped(token)
        holder.stopToken = token
        try {
            manager?.unregisterService(holder.listener) ?: registration.onStopped(token)
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            registration.onStopped(token) // уже не зарегистрирован — операции нет
        }
    }

    private fun discover(me: Identity, token: Int) {
        val m = manager ?: return discovery.onStartFailed(token)
        lateinit var holder: Stoppable<NsdManager.DiscoveryListener>
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Mb10Log.event(TAG, "nsd.discovery_started")
                discovery.onStarted(token)
            }
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Mb10Log.warnEvent(TAG, "nsd.discovery_start_failed", "code" to errorCode)
                discovery.onStartFailed(token)
            }
            override fun onDiscoveryStopped(serviceType: String) = discovery.onStopped(holder.stopToken)
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = discovery.onStopped(holder.stopToken)

            override fun onServiceFound(info: NsdServiceInfo) {
                if (info.serviceName == myServiceName || identity?.publicKeyB64 != me.publicKeyB64) return
                Mb10Log.event(TAG, "nsd.service_found", "service" to info.serviceName)
                resolves.add(info)
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                Mb10Log.event(TAG, "nsd.service_lost", "service" to info.serviceName)
                resolves.remove(info.serviceName)
                table.lost(info.serviceName)
            }
        }
        holder = Stoppable(listener)
        activeDiscovery = holder
        try {
            m.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            Mb10Log.warnEvent(TAG, "nsd.discovery_start_failed", "error" to e.javaClass.simpleName)
            activeDiscovery = null
            discovery.onStartFailed(token)
        }
    }

    private fun stopDiscovery(token: Int) {
        val holder = activeDiscovery
        activeDiscovery = null
        if (holder == null) return discovery.onStopped(token)
        holder.stopToken = token
        try {
            manager?.stopServiceDiscovery(holder.listener) ?: discovery.onStopped(token)
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            discovery.onStopped(token) // поиск уже не шёл
        }
    }

    private fun resolve(info: NsdServiceInfo, token: Int) {
        val m = manager ?: return resolves.onFailed(token, busy = false)
        try {
            @Suppress("DEPRECATION") // resolveService с колбэком — единственный путь до API 34 (minSdk 26)
            m.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                    Mb10Log.warnEvent(TAG, "nsd.resolve_failed", "service" to info.serviceName, "code" to errorCode)
                    resolves.onFailed(token, busy = errorCode == NsdManager.FAILURE_ALREADY_ACTIVE)
                }
                override fun onServiceResolved(resolved: NsdServiceInfo) {
                    onResolved(resolved)
                    resolves.onResolved(token)
                }
            })
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            Mb10Log.warnEvent(TAG, "nsd.resolve_failed", "service" to info.serviceName, "error" to e.javaClass.simpleName)
            resolves.onFailed(token, busy = false)
        }
    }

    private fun onResolved(resolved: NsdServiceInfo) {
        val me = identity ?: return
        val pk = resolved.attributes["pk"]?.toString(Charsets.UTF_8) ?: return
        if (pk == me.publicKeyB64) return
        val cs = resolved.attributes["cs"]?.toString(Charsets.UTF_8) ?: ""
        val fac = resolved.attributes["fac"]?.toString(Charsets.UTF_8) ?: ""
        @Suppress("DEPRECATION") // host — до API 34 единственный адрес разрешённого сервиса
        val host = resolved.host?.hostAddress ?: return
        table.found(resolved.serviceName, PeerInfo(pk, cs, fac, host, resolved.port))
    }

    private fun deriveServiceName(pubKeyB64: String): String =
        "mb10-" + pubKeyB64.hashCode().toUInt().toString(16)
}
