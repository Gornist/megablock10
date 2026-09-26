package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.chat.ReadReceiptSetting
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/**
 * Настройки: адрес мастерского коллектора и код игры (если персонаж выдан не QR мастера), очередь неотправленных записей, узлы
 * сети, сведения об устройстве для архива журнала. Сохранение адреса или кода будит синхронизацию ([wakeSync]) — записи уходят
 * сразу, без ожидания следующего опроса.
 */
class SettingsViewModel(
    private val settings: CollectorSettings,
    pendingChanges: Flow<Int>,
    val peers: StateFlow<List<OnlinePlayer>>,
    private val wakeSync: () -> Unit,
    private val deviceInfo: suspend () -> String,
    private val readReceipts: ReadReceiptSetting? = null,
) : ViewModel() {
    /** «Отчёты о прочтении» (D4): выключен — свои не уходят, чужие не видны. */
    val readReceiptsEnabled: StateFlow<Boolean> = readReceipts?.enabled ?: MutableStateFlow(true)

    fun setReadReceipts(on: Boolean) { readReceipts?.set(on) }

    /** Записи, ещё не подтверждённые коллектором. */
    val pendingChanges: StateFlow<Int> = pendingChanges.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), 0)

    /** Адрес из сборки — подсказка в пустом поле. */
    val defaultUrl: String get() = settings.defaultUrl

    // Читаются при каждом показе экрана (не кэшируются): выдача персонажа или сброс сессии меняют их без перезапуска.
    fun collectorUrl(): String = settings.baseUrl() ?: ""
    fun gameSecret(): String = settings.gameSecret() ?: ""
    fun isProvisioned(): Boolean = settings.isProvisioned()
    fun isProvisionRejected(): Boolean = settings.isProvisionRejected()

    fun saveCollectorUrl(url: String) {
        settings.setBaseUrl(url)
        Mb10Log.event("Settings", "collector_url_saved", "url" to url)
        wakeSync()
    }

    fun saveGameSecret(secret: String) {
        settings.setGameSecret(secret.ifBlank { null })
        Mb10Log.event("Settings", "game_secret_saved", "empty" to secret.isBlank())
        wakeSync()
    }

    /** Сведения об устройстве и состоянии приложения для `device.txt` в архиве журнала (DeviceDiagnostics). */
    suspend fun deviceReport(): String = deviceInfo()
}
