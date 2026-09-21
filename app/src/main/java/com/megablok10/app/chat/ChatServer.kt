package com.megablok10.app.chat

import android.util.Log
import com.megablok10.app.breach.ClaimProtocol
import com.megablok10.app.call.CallProtocol
import com.megablok10.app.call.CallSignal
import com.megablok10.app.data.SlotClaimEntity
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val TAG = "ChatServer"

/** Самая длинная легитимная строка — SDP-предложение звонка (единицы КБ в base64); всё, что больше, — мусор или попытка забить память. */
private const val MAX_LINE_CHARS = 256 * 1024

/**
 * Читает одну строку до '\n', но не больше [maxChars] символов: BufferedReader.readLine()
 * накапливал бы строку без границы, пока клиент шлёт данные без перевода строки.
 * null — поток кончился без данных, либо строка длиннее лимита (отбрасываем целиком).
 */
internal fun readBoundedLine(input: java.io.InputStream, maxChars: Int): String? {
    val reader = BufferedReader(InputStreamReader(input, Charsets.UTF_8))
    val sb = StringBuilder()
    while (true) {
        val c = reader.read()
        if (c == -1) return if (sb.isEmpty()) null else sb.toString()
        if (c == '\n'.code) return sb.toString().trimEnd('\r')
        if (sb.length >= maxChars) return null
        sb.append(c.toChar())
    }
}

/**
 * Слушает входящие сообщения на порту, который сама же и выбирает (0 — ОС
 * назначает свободный). Один коннект = одно сообщение (см. ChatProtocol) —
 * поэтому accept-луп просто читает одну строку и закрывает сокет, без
 * долгоживущих соединений и их учёта. Сигналы звонка (CallProtocol) и заявки
 * на слот лута (ClaimProtocol) идут через тот же самый сокет — отдельный
 * сервер/порт под них не нужен, различаются они по магическому префиксу
 * первой же строки.
 */
class ChatServer(
    private val onMessage: (ChatWireMessage) -> Unit,
    private val onCallSignal: (CallSignal) -> Unit = {},
    private val onSlotClaim: (SlotClaimEntity) -> Unit = {},
    /** Строка известного протокола, но другой версии (телефон со старым/новым приложением): сообщается игроку, см. WireVersion. */
    private val onIncompatible: (String) -> Unit = {}
) {
    private var serverSocket: ServerSocket? = null
    private var job: Job? = null

    val port: Int get() = serverSocket?.localPort ?: -1

    fun start(scope: CoroutineScope) {
        val socket = ServerSocket(0)
        serverSocket = socket
        Log.i(TAG, "Слушаю входящие сообщения на порту ${socket.localPort}")
        job = scope.launch(Dispatchers.IO) {
            while (isActive) {
                val client = try {
                    socket.accept()
                } catch (e: Exception) {
                    break
                }
                launch(Dispatchers.IO) { handleClient(client) }
            }
        }
    }

    /**
     * Любой сбой одного соединения (молчащий клиент → SocketTimeoutException, обрыв,
     * исключение из колбэка) обязан оставаться внутри него. Раньше исключение уходило
     * из launch в родительскую корутину без обработчика — то есть любое устройство в
     * Wi-Fi, просто открывшее порт и промолчавшее 5 секунд, роняло приложение.
     */
    private fun handleClient(socket: Socket) {
        try {
            socket.use {
                it.soTimeout = 5000
                val line = readBoundedLine(it.getInputStream(), MAX_LINE_CHARS) ?: return
                val handled = ChatProtocol.decode(line)?.let(onMessage)
                    ?: CallProtocol.decode(line)?.let(onCallSignal)
                    ?: ClaimProtocol.decode(line)?.let(onSlotClaim)
                if (handled == null) onIncompatible(line)
            }
        } catch (e: Exception) {
            Log.w(TAG, "входящее соединение отброшено: ${e.message}")
        }
    }

    fun stop() {
        job?.cancel()
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            // сокет мог уже закрыться сам — не наша забота на остановке
        }
        serverSocket = null
    }
}
