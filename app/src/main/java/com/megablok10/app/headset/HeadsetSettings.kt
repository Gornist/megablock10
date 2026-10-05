package com.megablok10.app.headset

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Порт WebSocket-сервера очков по умолчанию (docs/netrun-phone-link.md). */
const val HEADSET_DEFAULT_PORT = 7420

/**
 * Настройка связи с очками. [enabled] по умолчанию выключено: включение по умолчанию — отдельное слияние после живой проверки.
 * [address] — `host` или `host:port` очков, [token] — одноразовый ключ канала (латиница, цифры, `-`, `_`): он попадает в адрес и больше никуда,
 * в журнал приложения не пишется.
 */
data class HeadsetConfig(val enabled: Boolean = false, val address: String = "", val token: String = "") {
    /** `ws://host:port/?token=…` или null, если адрес или токен не годятся. Токен в query: сервер очков (Godot) заголовки рукопожатия не отдаёт. */
    fun url(): String? {
        val m = ADDRESS.matchEntire(address.trim()) ?: return null
        val port = m.groupValues[2].ifEmpty { HEADSET_DEFAULT_PORT.toString() }.toIntOrNull()?.takeIf { it in 1..MAX_PORT } ?: return null
        if (!TOKEN.matches(token)) return null
        return "ws://${m.groupValues[1]}:$port/?token=$token"
    }

    /** Адрес без токена — единственное, что можно писать в журнал. */
    fun hostPort(): String {
        val m = ADDRESS.matchEntire(address.trim()) ?: return "?"
        return "${m.groupValues[1]}:${m.groupValues[2].ifEmpty { HEADSET_DEFAULT_PORT.toString() }}"
    }

    private companion object {
        val ADDRESS = Regex("""([A-Za-z0-9.\-]+)(?::(\d{1,5}))?""")
        val TOKEN = Regex("""[A-Za-z0-9_\-]{1,128}""")
        const val MAX_PORT = 65535
    }
}

/** Настройки очков и «до какого времени прочитан диалог» (для счётчика непрочитанного в очках) поверх SharedPreferences `headset_prefs`. */
class HeadsetSettings(private val prefs: SharedPreferences) : HeadsetReadState {
    private val _config = MutableStateFlow(load())
    val config: StateFlow<HeadsetConfig> = _config.asStateFlow()

    private fun load() = HeadsetConfig(
        enabled = prefs.getBoolean(KEY_ENABLED, false),
        address = prefs.getString(KEY_ADDRESS, "").orEmpty(),
        token = prefs.getString(KEY_TOKEN, "").orEmpty(),
    )

    fun update(transform: (HeadsetConfig) -> HeadsetConfig) {
        val next = transform(_config.value)
        // commit(), не apply(): настройка должна пережить убийство процесса сразу после правки.
        prefs.edit().putBoolean(KEY_ENABLED, next.enabled).putString(KEY_ADDRESS, next.address).putString(KEY_TOKEN, next.token).commit()
        _config.value = next
    }

    override fun lastRead(thread: String): Long? = prefs.getLong(READ_PREFIX + thread, NONE).takeIf { it != NONE }

    override fun setLastRead(thread: String, upToMs: Long) {
        prefs.edit().putLong(READ_PREFIX + thread, upToMs).apply()
    }

    companion object {
        const val PREFS = "headset_prefs"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_ADDRESS = "address"
        private const val KEY_TOKEN = "token"
        private const val READ_PREFIX = "read_"
        private const val NONE = Long.MIN_VALUE
    }
}
