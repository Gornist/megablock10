package com.megablok10.app.collector

import android.content.Context

private const val PREFS = "collector_prefs"
private const val KEY_BASE_URL = "base_url"
private const val KEY_GAME_SECRET = "game_secret"

private const val KEY_PROVISIONED = "provisioned"
private const val KEY_USED_PROVISIONS = "used_provisions"

/**
 * Адрес сервера дашборда в игровой сети по умолчанию — задаётся при сборке (`mb10.collectorUrl` в local.properties, см. README), в публичном
 * коде реального адреса нет. Пусто — не задан: отправка выключена, пока адрес не придёт по QR персонажа (ProvisionStore) или не введён в Настройках.
 */
val DEFAULT_COLLECTOR_URL: String get() = com.megablok10.app.BuildConfig.DEFAULT_COLLECTOR_URL

/**
 * Адрес ноутбука мастера (коллектора) в игровой сети — вводится вручную в
 * Настройках. mDNS сознательно не делали (см. admin-web/README.md), QR-код
 * с адресом — более надёжный путь на LARP-скорости, но сама форма ручного
 * ввода нужна в любом случае как запасной вариант.
 */
object CollectorSettings {
    /**
     * Пока адрес ни разу не задавали — адрес из сборки [DEFAULT_COLLECTOR_URL] (если он задан). Если его явно очистили (пустая строка) или
     * адреса нет нигде — null: коллектор отключён, ChangeRecordSync ничего никуда не шлёт и просто копит очередь локально.
     */
    fun baseUrl(context: Context): String? {
        val p = prefs(context)
        if (!p.contains(KEY_BASE_URL)) return DEFAULT_COLLECTOR_URL.takeIf { it.isNotBlank() }
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

    /** Настройки пришли по QR персонажа от мастера (ProvisionStore): в Настройках адрес и код игры только читаются. Снимается сбросом сессии. */
    fun isProvisioned(context: Context): Boolean = prefs(context).getBoolean(KEY_PROVISIONED, false)
    fun setProvisioned(context: Context, value: Boolean) { prefs(context).edit().putBoolean(KEY_PROVISIONED, value).apply() }

    /**
     * Идентификаторы уже применённых QR персонажа. Хранятся здесь, а не в Room и не в личности: сброс сессии стирает личность, но тот же QR
     * второй раз применить нельзя — новый выдаёт мастер.
     */
    fun isProvisionUsed(context: Context, id: String): Boolean = prefs(context).getStringSet(KEY_USED_PROVISIONS, emptySet())?.contains(id) == true
    fun markProvisionUsed(context: Context, id: String) {
        val p = prefs(context)
        val next = (p.getStringSet(KEY_USED_PROVISIONS, emptySet()) ?: emptySet()) + id
        p.edit().putStringSet(KEY_USED_PROVISIONS, next).apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
