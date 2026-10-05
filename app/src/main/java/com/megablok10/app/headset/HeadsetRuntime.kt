package com.megablok10.app.headset

import android.content.Context
import android.net.wifi.WifiManager
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.sound.SoundMirror
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/** Пауза перед очередной попыткой подключиться к очкам: растёт, пока не получается, и сбрасывается после удачного соединения. */
class HeadsetBackoff(private val stepsMs: LongArray = longArrayOf(1_000, 2_000, 5_000, 10_000, 15_000)) {
    private var attempt = 0
    fun next(): Long = stepsMs[minOf(attempt++, stepsMs.lastIndex)]
    fun reset() { attempt = 0 }
}

/**
 * Связь телефона с очками (docs/netrun-phone-link.md): телефон — WebSocket-клиент, очки — сервер. Работает, пока включён переключатель
 * ([HeadsetSettings]) и идёт сетевая сессия: запускается как задача сессии (MeshSession.sessionTasks → SessionController), поэтому живёт под
 * foreground-сервисом и при выключенном экране. Пока Wi-Fi-блокировка ([WifiManager.WifiLock]) удерживается — радио не засыпает.
 *
 * Переподключение с нарастающей паузой ([HeadsetBackoff]). Токен — в адресе (`?token=`), в журнал не пишется: там только `host:port`.
 * Кадры разбирает [HeadsetCodec], логику — [HeadsetMirror]. Как [SoundMirror] отдаёт звуки очкам, пока они слушают (после `hello_ack`).
 */
class HeadsetRuntime(
    private val app: Context,
    private val settings: HeadsetSettings,
    private val mirrorFactory: (onReady: (Boolean) -> Unit) -> HeadsetMirror,
) : SoundMirror {
    private val client = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_S, TimeUnit.SECONDS)
        .pingInterval(PING_INTERVAL_S, TimeUnit.SECONDS) // обрыв канала (очки выключили, ушли из Wi-Fi) замечаем сами, не ждём TCP-таймаута
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    @Volatile private var ready = false
    @Volatile private var socket: WebSocket? = null
    private var wifiLock: WifiManager.WifiLock? = null

    /** Очки слушают (получили `hello` и ответили `hello_ack`): звуки играют они, телефон молчит. */
    override val takesOver: Boolean get() = ready

    override fun onSound(kind: String) {
        if (ready) sendFrame(HeadsetOut.Sound(kind))
    }

    private fun sendFrame(frame: HeadsetOut): Boolean {
        val ws = socket ?: return false
        val text = HeadsetCodec.encode(frame)
        return text.length <= MAX_FRAME_CHARS && ws.send(text)
    }

    /** Задача сессии: следит за настройкой и держит соединение, пока оно нужно. Возвращается сразу (работает в [scope]). */
    fun start(scope: CoroutineScope) {
        scope.launch {
            try {
                settings.config.collectLatest { cfg ->
                    val url = cfg.url()
                    if (!cfg.enabled || url == null) {
                        if (cfg.enabled) Mb10Log.warnEvent(TAG, "headset.bad_config", "address" to cfg.address)
                        return@collectLatest
                    }
                    holdWifi(true)
                    try {
                        runConnection(url, cfg.hostPort())
                    } finally {
                        withContext(NonCancellable) { holdWifi(false) }
                    }
                }
            } finally {
                ready = false
            }
        }
    }

    private suspend fun runConnection(url: String, hostPort: String) {
        val backoff = HeadsetBackoff()
        Mb10Log.event(TAG, "headset.enabled", "to" to hostPort)
        while (currentCoroutineContext().isActive) {
            val connectedAt = System.currentTimeMillis()
            val wasReady = connectOnce(url, hostPort)
            if (wasReady || System.currentTimeMillis() - connectedAt > STABLE_MS) backoff.reset()
            val pause = backoff.next()
            Mb10Log.event(TAG, "headset.reconnect_in", "ms" to pause)
            delay(pause)
        }
    }

    /** Одно соединение до обрыва. true — очки успели ответить `hello_ack`. */
    private suspend fun connectOnce(url: String, hostPort: String): Boolean = coroutineScope {
        val commands = Channel<HeadsetCommand>(Channel.UNLIMITED)
        val closed = CompletableDeferred<Unit>()
        var wasReady = false
        val mirror = mirrorFactory { value -> ready = value; if (value) wasReady = true }
        var serving: Job? = null
        val ws = client.newWebSocket(
            Request.Builder().url(url).build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    Mb10Log.event(TAG, "headset.open", "to" to hostPort)
                    socket = webSocket
                    serving = launch { mirror.serve({ frame -> sendFrame(frame) }, commands) }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    HeadsetCodec.decode(text)?.let { commands.trySend(it) }
                        ?: Mb10Log.d(TAG, "headset.frame_ignored chars=${text.length}")
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    Mb10Log.event(TAG, "headset.closed", "code" to code)
                    closed.complete(Unit)
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Mb10Log.warnEvent(TAG, "headset.failed", "to" to hostPort, "error" to t.javaClass.simpleName, "http" to response?.code)
                    closed.complete(Unit)
                }
            },
        )
        try {
            closed.await()
        } finally {
            ready = false
            socket = null
            serving?.cancel()
            commands.close()
            ws.cancel()
        }
        wasReady
    }

    private fun holdWifi(on: Boolean) {
        if (on == (wifiLock != null)) return
        if (on) {
            val wm = app.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            @Suppress("DEPRECATION") // WIFI_MODE_FULL_HIGH_PERF: «низкая задержка» работает только при включённом экране, а канал нужен и в кармане
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "mb10-headset").apply { setReferenceCounted(false); acquire() }
        } else {
            try { wifiLock?.release() } catch (e: RuntimeException) { /* уже отпущен */ }
            wifiLock = null
        }
    }

    private companion object {
        const val TAG = "Headset"
        const val CONNECT_TIMEOUT_S = 5L
        const val PING_INTERVAL_S = 15L
        const val STABLE_MS = 10_000L
    }
}
