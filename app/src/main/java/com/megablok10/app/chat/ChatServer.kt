package com.megablok10.app.chat

import android.util.Log
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

/**
 * Слушает входящие сообщения на порту, который сама же и выбирает (0 — ОС
 * назначает свободный). Один коннект = одно сообщение (см. ChatProtocol) —
 * поэтому accept-луп просто читает одну строку и закрывает сокет, без
 * долгоживущих соединений и их учёта.
 */
class ChatServer(private val onMessage: (ChatWireMessage) -> Unit) {
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

    private fun handleClient(socket: Socket) {
        socket.use {
            it.soTimeout = 5000
            val line = BufferedReader(InputStreamReader(it.getInputStream(), Charsets.UTF_8)).readLine() ?: return
            ChatProtocol.decode(line)?.let(onMessage)
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
