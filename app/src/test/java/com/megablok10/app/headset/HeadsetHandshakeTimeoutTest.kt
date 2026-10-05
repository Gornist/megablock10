package com.megablok10.app.headset

import java.net.ServerSocket
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Очки приняли TCP и молчат (игра зависла): попытка подключения должна закончиться ошибкой, а не висеть бесконечно. */
class HeadsetHandshakeTimeoutTest {
    @Test fun clientTimesOutWhenGlassesAcceptTcpButNeverAnswerTheHandshake() {
        ServerSocket(0).use { server ->
            val accepted = Thread { runCatching { server.accept().use { Thread.sleep(HOLD_MS) } } }.apply { isDaemon = true; start() }
            val failed = CountDownLatch(1)
            val client = headsetHttpClient(handshakeTimeoutS = 1)
            val ws = client.newWebSocket(
                Request.Builder().url("http://127.0.0.1:${server.localPort}/?token=t").build(),
                object : WebSocketListener() {
                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = failed.countDown()
                },
            )
            val ok = failed.await(WAIT_S, TimeUnit.SECONDS)
            ws.cancel()
            accepted.interrupt()
            client.dispatcher.executorService.shutdown()
            assertTrue("рукопожатие не оборвалось по таймауту", ok)
        }
    }

    /** Таймаут чтения относится только к рукопожатию: молчащий, но живой канал (очки не шлют кадров) не должен рваться. */
    @Test fun openChannelSurvivesSilenceLongerThanTheHandshakeTimeout() {
        ServerSocket(0).use { server ->
            val server101 = Thread {
                runCatching {
                    server.accept().use { s ->
                        val lines = s.getInputStream().bufferedReader()
                        val key = generateSequence { lines.readLine() }.takeWhile { it.isNotEmpty() }
                            .first { it.startsWith("Sec-WebSocket-Key:", ignoreCase = true) }.substringAfter(":").trim()
                        val accept = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + WS_GUID).toByteArray()))
                        s.getOutputStream().write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n\r\n".toByteArray())
                        s.getOutputStream().flush()
                        Thread.sleep(HOLD_MS)
                    }
                }
            }.apply { isDaemon = true; start() }
            val opened = CountDownLatch(1)
            val failed = CountDownLatch(1)
            val client = headsetHttpClient(handshakeTimeoutS = 1)
            val ws = client.newWebSocket(
                Request.Builder().url("http://127.0.0.1:${server.localPort}/?token=t").build(),
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) = opened.countDown()
                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = failed.countDown()
                },
            )
            assertTrue("канал не открылся", opened.await(WAIT_S, TimeUnit.SECONDS))
            val dropped = failed.await(3, TimeUnit.SECONDS) // втрое дольше таймаута чтения
            ws.cancel()
            server101.interrupt()
            client.dispatcher.executorService.shutdown()
            assertTrue("открытый канал оборвался по таймауту чтения", !dropped)
        }
    }

    @Test fun defaultClientLimitsTheHandshakeAndKeepsPing() {
        val client = headsetHttpClient()
        assertEquals(HANDSHAKE_TIMEOUT_S * 1000, client.readTimeoutMillis.toLong())
        assertTrue(client.pingIntervalMillis > 0)
    }

    private companion object {
        const val HOLD_MS = 20_000L
        const val WAIT_S = 8L
        const val WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    }
}
