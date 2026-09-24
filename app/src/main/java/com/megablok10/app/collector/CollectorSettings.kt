package com.megablok10.app.collector

import android.content.SharedPreferences

// Имена ключей — те же, что были: по ним лежат данные на телефонах, а стенд e2e читает shared_prefs/collector_prefs.xml напрямую.
private const val KEY_BASE_URL = "base_url"
private const val KEY_GAME_SECRET = "game_secret"
private const val KEY_PROVISIONED = "provisioned"
private const val KEY_USED_PROVISIONS = "used_provisions"
private const val KEY_PROVISION_REJECTED = "provision_rejected"
private const val KEY_PROVISION_IN_PROGRESS = "provision_in_progress"

/**
 * Адрес ноутбука мастера (коллектора) в игровой сети и код игры. Обычно приходят по QR персонажа (ProvisionStore), форма ручного
 * ввода в Настройках — запасной вариант (mDNS сознательно не делали, см. admin-web/README.md). Хранится в SharedPreferences
 * `collector_prefs` ([prefs] передаёт корень композиции).
 *
 * [defaultUrl] — адрес из сборки (`mb10.collectorUrl` в local.properties, см. README), в публичном коде реального адреса нет.
 * Пусто — не задан: отправка выключена, пока адрес не придёт по QR персонажа или не будет введён в Настройках.
 */
class CollectorSettings(private val prefs: SharedPreferences, val defaultUrl: String) {
    /**
     * Пока адрес ни разу не задавали — [defaultUrl] (если он задан). Если его явно очистили (пустая строка) или адреса нет нигде —
     * null: коллектор отключён, синхронизация ничего никуда не шлёт и просто копит очередь локально.
     */
    fun baseUrl(): String? {
        if (!prefs.contains(KEY_BASE_URL)) return defaultUrl.takeIf { it.isNotBlank() }
        return prefs.getString(KEY_BASE_URL, null)?.takeIf { it.isNotBlank() }
    }

    /** Пустая строка сохраняется как есть — это явное «отключить коллектор», в отличие от «не задавали» (тогда действует адрес по умолчанию). */
    fun setBaseUrl(url: String?) {
        prefs.edit().putString(KEY_BASE_URL, url?.trim()?.trimEnd('/').orEmpty()).apply()
    }

    /** null — GAME_SECRET на сервере не настроен (или мастер не раздал), заголовок X-Game-Secret не шлём вовсе. */
    fun gameSecret(): String? = prefs.getString(KEY_GAME_SECRET, null)?.takeIf { it.isNotBlank() }

    fun setGameSecret(secret: String?) {
        prefs.edit().putString(KEY_GAME_SECRET, secret?.trim()).apply()
    }

    /** Настройки пришли по QR персонажа от мастера (ProvisionStore): в Настройках адрес и код игры только читаются. Снимается сбросом сессии. */
    fun isProvisioned(): Boolean = prefs.getBoolean(KEY_PROVISIONED, false)
    fun setProvisioned(value: Boolean) { prefs.edit().putBoolean(KEY_PROVISIONED, value).apply() }

    /** Сервер отказал в коде персонажа (применён на другом телефоне или заменён новой выдачей): в Настройках висит плашка «обратитесь к мастеру» до сброса сессии. */
    fun isProvisionRejected(): Boolean = prefs.getBoolean(KEY_PROVISION_REJECTED, false)
    fun setProvisionRejected(value: Boolean) { prefs.edit().putBoolean(KEY_PROVISION_REJECTED, value).apply() }

    /**
     * Идентификаторы уже применённых QR персонажа. Хранятся здесь, а не в Room и не в личности: сброс сессии стирает личность, но тот же QR
     * второй раз применить нельзя — новый выдаёт мастер.
     */
    fun isProvisionUsed(id: String): Boolean = prefs.getStringSet(KEY_USED_PROVISIONS, emptySet())?.contains(id) == true
    /**
     * Начало выдачи по QR [raw] с id [id]: код помечается использованным и запоминается как «в процессе» — одной синхронной записью.
     * Если процесс умрёт до [finishProvision], выдачу доделают при запуске (ProvisionStore.resumeInterrupted), а не сочтут QR
     * «уже использованным» при несозданном персонаже.
     */
    fun beginProvision(id: String, raw: String) {
        val next = (prefs.getStringSet(KEY_USED_PROVISIONS, emptySet()) ?: emptySet()) + id
        prefs.edit().putStringSet(KEY_USED_PROVISIONS, next).putString(KEY_PROVISION_IN_PROGRESS, raw).commit()
    }

    /** QR выдачи, применение которого началось и не закончилось; null — такого нет. */
    fun provisionInProgress(): String? = prefs.getString(KEY_PROVISION_IN_PROGRESS, null)

    /** Выдача закончена. Синхронно — заодно на диск уходят адрес сервера и код игры, записанные по ходу выдачи. */
    fun finishProvision() {
        prefs.edit().remove(KEY_PROVISION_IN_PROGRESS).commit()
    }

    companion object {
        /** Файл настроек — тот же, что был у объекта CollectorSettings. */
        const val PREFS = "collector_prefs"
    }
}
