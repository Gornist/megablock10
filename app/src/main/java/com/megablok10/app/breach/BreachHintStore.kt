package com.megablok10.app.breach

import android.content.SharedPreferences

/**
 * «Подсказка про цепочку показана»: механику объясняем новичку один раз — строкой над сеткой до первого тапа (не диалогом: он
 * заблокировал бы таймер). Общая для взлома контейнера и дешифровки шарда.
 */
class BreachHintStore(private val prefs: SharedPreferences) {
    fun isSeen(): Boolean = prefs.getBoolean(KEY, false)

    fun markSeen() {
        prefs.edit().putBoolean(KEY, true).apply()
    }

    companion object {
        const val PREFS = "ux_prefs"
        private const val KEY = "breach_hint_seen"
    }
}
