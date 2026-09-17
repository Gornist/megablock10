package com.megablok10.app.presence

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/**
 * Есть ли у устройства сейчас Wi-Fi-соединение — игра всегда офлайн на
 * изолированной локальной сети, поэтому "в сети" здесь значит "подключён к
 * Wi-Fi площадки", а не "виден хотя бы один игрок". Используется как гейт
 * перед взломом контейнера (ревизия v9 §5) — без этого можно было бы
 * обойти сигнал СБ авиарежимом, взломать контейнер офлайн и включить связь
 * обратно уже после результата.
 */
object MeshLink {
    fun isOnline(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }
}
