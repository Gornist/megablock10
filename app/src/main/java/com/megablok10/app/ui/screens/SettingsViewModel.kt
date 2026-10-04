package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.megablok10.app.chat.ReadReceiptSetting
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.log.LogStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

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
    private val logStore: LogStore,
    private val readReceipts: ReadReceiptSetting? = null,
    /** Итог последней попытки коллектора (CollectorClient.reachable) — для плашки «Нет связи», M4.8 плана миграции. */
    val collectorReachable: StateFlow<Boolean> = MutableStateFlow(true),
) : ViewModel() {
    /** «Отчёты о прочтении» (D4): выключен — свои не уходят, чужие не видны. */
    val readReceiptsEnabled: StateFlow<Boolean> = readReceipts?.enabled ?: MutableStateFlow(true)

    fun setReadReceipts(on: Boolean) { readReceipts?.set(on) }

    /** Записи, ещё не подтверждённые коллектором. */
    val pendingChanges: StateFlow<Int> = pendingChanges.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_MS), 0)

    /** «Повторить» на плашке «Нет связи» — тот же будильник синка, что после сохранения адреса/кода. */
    fun retrySync() = wakeSync()

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

    private val _logSizeKb = MutableStateFlow(logStore.sizeBytes() / 1024)

    /** Размер журнала приложения, КБ. */
    val logSizeKb: StateFlow<Long> = _logSizeKb

    private val _logStatus = MutableStateFlow<String?>(null)

    /** Итог последнего действия с журналом («Метка записана», «Архив: N КБ»…); null — действий ещё не было. */
    val logStatus: StateFlow<String?> = _logStatus

    private fun refreshLogSize() {
        logStore.flush()
        _logSizeKb.value = logStore.sizeBytes() / 1024
    }

    /** Экран открыт заново: размер читается свежий, итог прошлого действия не показываем (раньше это состояние жило в экране). */
    fun onLogScreenShown() {
        _logStatus.value = null
        _logSizeKb.value = logStore.sizeBytes() / 1024
    }

    /** Метка «что я сейчас делаю» в журнал. false — текст пустой, ничего не записано. */
    fun markLog(text: String): Boolean {
        if (text.isBlank()) return false
        Mb10Log.event("MARK", "mark", "text" to text.trim())
        _logStatus.value = "Метка записана"
        viewModelScope.launch { refreshLogSize() }
        return true
    }

    fun clearLog() {
        logStore.clear()
        Mb10Log.event("Settings", "log_cleared")
        viewModelScope.launch { refreshLogSize(); _logStatus.value = "Журнал очищен" }
    }

    /** Собирает архив журнала с отчётом об устройстве; null — не вышло. Отправка архива (Intent) — дело экрана. */
    suspend fun exportLog(): File? {
        Mb10Log.event("Settings", "log_export_requested")
        val zip = withContext(Dispatchers.IO) { runCatching { logStore.exportZip(deviceReport()) }.getOrNull() }
        _logStatus.value = if (zip == null) "Не удалось собрать архив" else "Архив: ${zip.length() / 1024} КБ"
        return zip
    }

    /** Сведения об устройстве и состоянии приложения для `device.txt` в архиве журнала (DeviceDiagnostics). */
    suspend fun deviceReport(): String = deviceInfo()
}
