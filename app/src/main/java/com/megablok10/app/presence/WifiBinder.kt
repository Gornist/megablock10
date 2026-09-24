package com.megablok10.app.presence

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.net.Inet4Address

private const val TAG = "WifiBinder"

/**
 * Разовый провал `bindProcessToNetwork` встречается на некоторых прошивках (на живой проверке — Samsung, Android 16): сеть уже
 * доступна (`onAvailable` пришёл), но привязка в этот самый момент ещё не готова и возвращает false. Без повтора устройство
 * оставалось непривязанным всю сессию — трафик уходил, куда решит сама ОС (на той проверке иногда через мобильные данные), и
 * коллектор через раз отвечал таймаутом. Значения подобраны так, чтобы не спамить лог: несколько попыток за пару секунд.
 */
private val BIND_RETRY_DELAYS_MS = longArrayOf(200, 500, 1000, 2000)

/**
 * Привязывает весь трафик приложения к Wi-Fi (docs/network-spec.md, §7). Игровая сеть без интернета: Android считает такой Wi-Fi
 * «непроверенным» и при включённой мобильной передаче данных может пустить трафик приложения через сотовую сеть — тогда адреса
 * 10.10.x.x перестают отвечать, а чат, звонки и коллектор молчат. `requestNetwork` с транспортом Wi-Fi и `bindProcessToNetwork`
 * заставляют сокеты идти по Wi-Fi, не требуя ни INTERNET-проверки, ни VALIDATED.
 *
 * [onChanged] вызывается, когда сеть появилась, пропала или у неё сменился адрес (переподключение, новая аренда DHCP): NSD после
 * этого надо регистрировать заново, старые записи mDNS уже не действуют.
 */
class WifiBinder(private val app: Context) {
    private var manager: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var scope: CoroutineScope? = null
    private var retryJob: Job? = null

    @Volatile var boundNetwork: Network? = null
        private set

    /** Собственный IPv4-адрес в Wi-Fi (для сообщения серверу «где меня искать»), null — Wi-Fi нет. */
    @Volatile var ownIpv4: String? = null
        private set

    fun start(onChanged: () -> Unit) {
        stop()
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        Mb10Log.event(TAG, "wifi.start")
        manager = cm
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
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
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                // Ограниченные повторы в bind() уже отгорели, а привязки так и нет — capabilities-события (их Android шлёт по мере
                // того, как сеть «дозревает», например до VALIDATED) второй шанс на привязку, без опроса по таймеру.
                if (boundNetwork == null) bind(cm, network)
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
                retryJob?.cancel()
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

    /** attempt — только для лога: с какой попытки получилось (или не получилось после всех). */
    private fun bind(cm: ConnectivityManager, network: Network, attempt: Int = 0) {
        retryJob?.cancel()
        try {
            if (cm.bindProcessToNetwork(network)) {
                boundNetwork = network
                ownIpv4 = cm.getLinkProperties(network)?.linkAddresses?.map { it.address }?.filterIsInstance<Inet4Address>()?.firstOrNull()?.hostAddress
                Mb10Log.i(TAG, "привязано к Wi-Fi: network=$network ip=$ownIpv4 attempt=$attempt")
                return
            }
            Mb10Log.w(TAG, "bindProcessToNetwork вернул false для $network (попытка $attempt)")
        } catch (e: Exception) {
            Mb10Log.w(TAG, "не удалось привязаться к Wi-Fi: ${e.message} (попытка $attempt)")
        }
        scheduleRetry(cm, network, attempt)
    }

    /** Разовый провал не должен оставлять устройство непривязанным на всю сессию (см. комментарий у BIND_RETRY_DELAYS_MS). */
    private fun scheduleRetry(cm: ConnectivityManager, network: Network, attempt: Int) {
        if (attempt >= BIND_RETRY_DELAYS_MS.size) {
            Mb10Log.w(TAG, "не привязались к Wi-Fi после ${attempt + 1} попыток, жду следующего onAvailable/onCapabilitiesChanged")
            return
        }
        val s = scope ?: return
        retryJob = s.launch {
            delay(BIND_RETRY_DELAYS_MS[attempt])
            // За время ожидания сеть могла смениться или пропасть — привязываемся заново только если она всё ещё актуальна.
            if (boundNetwork == null && cm.getNetworkCapabilities(network) != null) bind(cm, network, attempt + 1)
        }
    }

    fun stop() {
        val cm = manager
        val cb = callback
        if (cm != null && cb != null) {
            try { cm.unregisterNetworkCallback(cb) } catch (e: Exception) { /* уже снят */ }
            try { cm.bindProcessToNetwork(null) } catch (e: Exception) { /* ignore */ }
        }
        scope?.cancel()
        scope = null
        retryJob = null
        callback = null
        manager = null
        boundNetwork = null
        ownIpv4 = null
    }
}
