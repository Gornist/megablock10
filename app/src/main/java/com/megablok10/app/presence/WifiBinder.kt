package com.megablok10.app.presence

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.megablok10.app.log.Mb10Log
import java.net.Inet4Address

private const val TAG = "WifiBinder"

/**
 * Привязывает весь трафик приложения к Wi-Fi (docs/network-spec.md, §7). Игровая сеть без интернета: Android считает такой Wi-Fi
 * «непроверенным» и при включённой мобильной передаче данных может пустить трафик приложения через сотовую сеть — тогда адреса
 * 10.10.x.x перестают отвечать, а чат, звонки и коллектор молчат. `requestNetwork` с транспортом Wi-Fi и `bindProcessToNetwork`
 * заставляют сокеты идти по Wi-Fi, не требуя ни INTERNET-проверки, ни VALIDATED.
 *
 * [onChanged] вызывается, когда сеть появилась, пропала или у неё сменился адрес (переподключение, новая аренда DHCP): NSD после
 * этого надо регистрировать заново, старые записи mDNS уже не действуют.
 */
object WifiBinder {
    private var manager: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    @Volatile var boundNetwork: Network? = null
        private set

    /** Собственный IPv4-адрес в Wi-Fi (для сообщения серверу «где меня искать»), null — Wi-Fi нет. */
    @Volatile var ownIpv4: String? = null
        private set

    fun start(context: Context, onChanged: () -> Unit) {
        stop()
        val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        Mb10Log.event(TAG, "wifi.start")
        manager = cm
        // INTERNET снимаем: сеть без выхода наружу — это и есть наша сеть; VALIDATED не требуем вовсе.
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Mb10Log.event(TAG, "wifi.available", "network" to network)
                bind(cm, network)
                onChanged()
            }
            override fun onLinkPropertiesChanged(network: Network, linkProperties: android.net.LinkProperties) {
                if (network == boundNetwork) {
                    val before = ownIpv4
                    ownIpv4 = linkProperties.linkAddresses.map { it.address }.filterIsInstance<Inet4Address>().firstOrNull()?.hostAddress
                    Mb10Log.event(TAG, "wifi.link_changed", "network" to network, "ipBefore" to before, "ip" to ownIpv4, "dns" to linkProperties.dnsServers.joinToString(",") { it.hostAddress ?: "?" }, "routes" to linkProperties.routes.size)
                    onChanged()
                }
            }
            override fun onLost(network: Network) {
                Mb10Log.event(TAG, "wifi.lost", "network" to network, "wasBound" to (network == boundNetwork))
                if (network == boundNetwork) {
                    boundNetwork = null
                    ownIpv4 = null
                    try { cm.bindProcessToNetwork(null) } catch (e: Exception) { Mb10Log.w(TAG, "не удалось снять привязку: ${e.message}") }
                    Mb10Log.i(TAG, "Wi-Fi пропал, привязка снята")
                }
                onChanged()
            }
        }
        callback = cb
        try {
            cm.requestNetwork(request, cb)
        } catch (e: SecurityException) {
            Mb10Log.w(TAG, "нет разрешения CHANGE_NETWORK_STATE, привязка к Wi-Fi недоступна: ${e.message}")
        }
    }

    private fun bind(cm: ConnectivityManager, network: Network) {
        try {
            if (cm.bindProcessToNetwork(network)) {
                boundNetwork = network
                ownIpv4 = cm.getLinkProperties(network)?.linkAddresses?.map { it.address }?.filterIsInstance<Inet4Address>()?.firstOrNull()?.hostAddress
                Mb10Log.i(TAG, "привязано к Wi-Fi: network=$network ip=$ownIpv4")
            } else {
                Mb10Log.w(TAG, "bindProcessToNetwork вернул false для $network")
            }
        } catch (e: Exception) {
            Mb10Log.w(TAG, "не удалось привязаться к Wi-Fi: ${e.message}")
        }
    }

    fun stop() {
        val cm = manager
        val cb = callback
        if (cm != null && cb != null) {
            try { cm.unregisterNetworkCallback(cb) } catch (e: Exception) { /* уже снят */ }
            try { cm.bindProcessToNetwork(null) } catch (e: Exception) { /* ignore */ }
        }
        callback = null
        manager = null
        boundNetwork = null
        ownIpv4 = null
    }
}
