package com.megablok10.app.voice

import android.content.SharedPreferences
import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private const val TAG = "VoicePlayer"

/** «Автопроигрывание голосовых»: после прослушанного сразу играет следующее непрослушанное от того же собеседника (как в Telegram). По умолчанию включено. */
class VoiceAutoplaySetting(private val prefs: SharedPreferences) {
    private val _enabled = MutableStateFlow(prefs.getBoolean(KEY, true))
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun set(on: Boolean) {
        prefs.edit().putBoolean(KEY, on).apply() // настройка экрана, не подтверждение для сети — достаточно apply()
        _enabled.value = on
        Mb10Log.event(TAG, "voice.autoplay_setting", "enabled" to on)
    }

    companion object {
        /** Тот же файл настроек, что у отчётов о прочтении: новый ключ, прежние не тронуты. */
        const val PREFS = "chat_prefs"
        private const val KEY = "voice_autoplay"
    }
}
