package com.megablok10.app.presence

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.util.Log
import com.megablok10.app.identity.Identity
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private const val SERVICE_TYPE = "_mb10chat._tcp."
private const val TAG = "PresenceService"

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

    // Источник правды — потокобезопасная карта (колбэки NSD приходят не из главного потока);
    // _peers лишь публикует её снимок при каждом изменении.
    private val peerMap = ConcurrentHashMap<String, PeerInfo>()
    private val _peers = MutableStateFlow<List<PeerInfo>>(emptyList())
    val peers: StateFlow<List<PeerInfo>> = _peers.asStateFlow()

    private fun publishPeers() {
        _peers.value = peerMap.values.toList()
    }

    fun start(context: Context, identity: Identity, chatPort: Int) {
        stop()

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
                        peerMap[resolved.serviceName] = PeerInfo(pk, cs, fac, host, resolved.port, System.currentTimeMillis())
                        publishPeers()
                    }
                })
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                peerMap.remove(info.serviceName)
                publishPeers()
            }
        }
        discoveryListener = discListener
        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discListener)
    }

    fun stop() {
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

        registrationListener = null
        discoveryListener = null
        multicastLock = null
        nsdManager = null
        myServiceName = null
        peerMap.clear()
        publishPeers()
    }

    private fun deriveServiceName(pubKeyB64: String): String =
        "mb10-" + pubKeyB64.hashCode().toUInt().toString(16)
}
