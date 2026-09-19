package com.megablok10.app.qr

import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * Шина для подачи "отсканированной" QR-строки без камеры — нужна для
 * прогона на эмуляторах (см. DebugQrReceiver в debug-сборке). В release-сборке
 * никто в неё не публикует: приёмник объявлен только в src/debug.
 */
object DebugQrBus {
    val events = MutableSharedFlow<String>(extraBufferCapacity = 8)
}
