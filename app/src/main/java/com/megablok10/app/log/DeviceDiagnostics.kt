package com.megablok10.app.log

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import com.megablok10.app.BuildConfig
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.presence.WifiBinder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Сведения об устройстве и периодический «снимок состояния» в журнал. Снимок раз в [SNAPSHOT_EVERY_MS] нужен затем, что многие
 * проблемы на живых телефонах не вызывают событий (Wi-Fi тихо деградировал, экономия батареи усыпила приложение, очередь копится):
 * по снимкам видно, что именно менялось между двумя событиями.
 */
object DeviceDiagnostics {
    private const val TAG = "Snapshot"
    private const val SNAPSHOT_EVERY_MS = 30_000L

    @Volatile var foreground: Boolean = false

    /** Строка в начало журнала: версия сборки и устройство. */
    fun header(): String =
        "app=${BuildConfig.VERSION_NAME} build=${if (BuildConfig.DEBUG) "debug" else "release"} " +
            "device=\"${Build.MANUFACTURER} ${Build.MODEL}\" android=${Build.VERSION.RELEASE} sdk=${Build.VERSION.SDK_INT} " +
            "collector=${BuildConfig.DEFAULT_COLLECTOR_URL.ifBlank { "-" }}"

    /** Текст device.txt в экспортируемом архиве. */
    suspend fun deviceReport(context: Context): String {
        val id = IdentityManager.current(context)
        return buildString {
            appendLine("время экспорта: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss XXX", java.util.Locale.US).format(java.util.Date())}")
            appendLine(header())
            appendLine("игрок: ${id?.callsign ?: "-"} фракция=${id?.faction ?: "-"} ключ=…${Mb10Log.short(id?.publicKeyB64)}")
            appendLine("часовой пояс: ${java.util.TimeZone.getDefault().id}")
            appendLine("экран/производитель: ${Build.BRAND} ${Build.DEVICE} ${Build.HARDWARE}")
            appendLine("последний снимок: ${snapshotLine(context)}")
        }
    }

    /** Запускает периодический снимок в переданном скоупе (останавливается вместе с ним). */
    fun startSnapshots(context: Context, scope: CoroutineScope) {
        val app = context.applicationContext
        scope.launch {
            while (true) {
                runCatching { Mb10Log.i(TAG, snapshotLine(app)) }.onFailure { Mb10Log.w(TAG, "снимок не собрался: ${it.message}") }
                delay(SNAPSHOT_EVERY_MS)
            }
        }
    }

    /** Одна строка со всем, что нужно, чтобы понять состояние телефона в этот момент. */
    private suspend fun snapshotLine(context: Context): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val wifi = wifiSignal(cm)
        val outbox = runCatching { OutboxStore.pending(context) }.getOrNull()
        val id = IdentityManager.current(context)
        return "snapshot fg=$foreground me=${Mb10Log.short(id?.publicKeyB64)} " +
            "wifiBound=${WifiBinder.boundNetwork != null} ip=${WifiBinder.ownIpv4 ?: "-"} nets=${networkKinds(cm)} " +
            "rssi=${wifi.rssi ?: "-"} freqMHz=${wifi.freq ?: "-"} linkMbps=${wifi.linkMbps ?: "-"} " +
            "chatPort=${ChatStore.listeningPort} peers=${PresenceService.describePeers()} outbox=${outbox ?: "-"} " +
            "sync=${ChangeRecordStore.lastSyncSummary} ${powerAndMemory(context)}"
    }

    /** Какие сети сейчас есть: `wifi:IV` — Wi-Fi с признаками INTERNET и VALIDATED (у игровой сети без выхода наружу их не будет). */
    @Suppress("DEPRECATION")
    private fun networkKinds(cm: ConnectivityManager?): List<String> = cm?.allNetworks.orEmpty().mapNotNull { n ->
        val c = cm?.getNetworkCapabilities(n) ?: return@mapNotNull null
        val kind = when {
            c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cell"
            c.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        val flags = (if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) "I" else "") +
            (if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) "V" else "")
        "$kind:$flags"
    }

    private class WifiSignal(val rssi: Int?, val freq: Int?, val linkMbps: Int?)

    /**
     * Уровень сигнала, частота и скорость Wi-Fi — из параметров самой сети. WifiManager.getConnectionInfo здесь не годится: его вызов
     * раз в 30 секунд в фоне мешал связи (на прогонах стенда ломались доставки), поэтому читаем только ConnectivityManager.
     * transportInfo и signalStrength появились в Android 10; на более старых телефонах значений просто не будет.
     */
    @Suppress("DEPRECATION")
    private fun wifiSignal(cm: ConnectivityManager?): WifiSignal {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return WifiSignal(null, null, null)
        val caps = cm?.allNetworks.orEmpty().mapNotNull { cm?.getNetworkCapabilities(it) }.firstOrNull { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) }
        val info = caps?.transportInfo as? WifiInfo
        val rssi = caps?.signalStrength?.takeIf { it != Int.MIN_VALUE } ?: info?.rssi
        return WifiSignal(rssi, info?.frequency?.takeIf { it > 0 }, info?.linkSpeed?.takeIf { it > 0 })
    }

    private fun powerAndMemory(context: Context): String {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.let { it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 100 / it.getIntExtra(BatteryManager.EXTRA_SCALE, 100) }
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status?.let { it == BatteryManager.BATTERY_STATUS_CHARGING || it == BatteryManager.BATTERY_STATUS_FULL }
        val rt = Runtime.getRuntime()
        return "battery=${level ?: "-"}% charging=${charging ?: "-"} powerSave=${pm?.isPowerSaveMode} doze=${pm?.isDeviceIdleMode} " +
            "heapMB=${(rt.totalMemory() - rt.freeMemory()) / 1_048_576}/${rt.maxMemory() / 1_048_576}"
    }
}
