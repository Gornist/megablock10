package com.megablok10.app.collector

import android.content.Context

private const val PREFS = "collector_prefs"
private const val KEY_BASE_URL = "base_url"
private const val KEY_GAME_SECRET = "game_secret"

/** Адрес сервера дашборда в игровой сети (docs/network-spec.md): фиксированный IP локального сервера и порт дашборда. */
const val DEFAULT_COLLECTOR_URL = "http://10.10.0.10:2517"

/**
 * Адрес ноутбука мастера (коллектора) в игровой сети — вводится вручную в
 * Настройках. mDNS сознательно не делали (см. admin-web/README.md), QR-код
 * с адресом — более надёжный путь на LARP-скорости, но сама форма ручного
 * ввода нужна в любом случае как запасной вариант.
 */
object CollectorSettings {
    /**
     * Пока адрес ни разу не задавали — стандартный адрес игровой сети [DEFAULT_COLLECTOR_URL]. Если его явно очистили (пустая строка) —
     * null: коллектор отключён, ChangeRecordSync ничего никуда не шлёт и просто копит очередь локально.
     */
    fun baseUrl(context: Context): String? {
        val p = prefs(context)
        if (!p.contains(KEY_BASE_URL)) return DEFAULT_COLLECTOR_URL
        return p.getString(KEY_BASE_URL, null)?.takeIf { it.isNotBlank() }
    }

    /** Пустая строка сохраняется как есть — это явное «отключить коллектор», в отличие от «не задавали» (тогда действует адрес по умолчанию). */
    fun setBaseUrl(context: Context, url: String?) {
        prefs(context).edit().putString(KEY_BASE_URL, url?.trim()?.trimEnd('/').orEmpty()).apply()
    }

    /** null — GAME_SECRET на сервере не настроен (или мастер не раздал), заголовок X-Game-Secret не шлём вовсе. */
    fun gameSecret(context: Context): String? =
        prefs(context).getString(KEY_GAME_SECRET, null)?.takeIf { it.isNotBlank() }

    fun setGameSecret(context: Context, secret: String?) {
        prefs(context).edit().putString(KEY_GAME_SECRET, secret?.trim()).apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
