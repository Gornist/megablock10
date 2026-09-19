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
    /**
     * Смотрим на ВСЕ подключённые сети, а не только на активную по умолчанию: Wi-Fi площадки почти всегда без интернета, и при включённых
     * мобильных данных Android делает основной именно мобильную сеть — прежняя проверка activeNetwork тогда ошибочно писала «нет связи»,
     * хотя телефон подключён к сети игры.
     */
    @Suppress("DEPRECATION")
    fun isOnline(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return cm.allNetworks.any { network ->
            cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
    }
}
