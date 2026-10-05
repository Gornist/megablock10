package com.megablok10.kit.net

import com.megablok10.kit.log.RecordingLog
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Отправка одной строки по-настоящему, через сокет на localhost. */
class LineSocketClientTest {
    private val log = RecordingLog()
    private val client = LineSocketClient(log)

    @Test fun lineArrivesAsUtf8WithSingleNewline() {
        ServerSocket(0).use { server ->
            val received = Executors.newSingleThreadExecutor().submit<ByteArray> {
                server.accept().use { it.getInputStream().readBytes() }
            }
            val line = "MB10CHAT:v1:DM:привет — мир"
            assertEquals(SendOutcome.DELIVERED, client.sendLineOutcome("127.0.0.1", server.localPort, line))
            assertArrayEquals((line + "\n").toByteArray(Charsets.UTF_8), received.get(5, TimeUnit.SECONDS))
        }
    }

    @Test fun closedPortIsNotReached() {
        val port = ServerSocket(0).use { it.localPort }
        assertEquals(SendOutcome.NOT_REACHED, client.sendLineOutcome("127.0.0.1", port, "x", timeoutMs = 1000))
        assertFalse(client.sendLine("127.0.0.1", port, "x", timeoutMs = 1000))
        assertTrue(log.has("W/Socket send.not_reached"))
    }

    /** Сокет, у которого connect «не дождался ответа»: так ведёт себя телефон с уснувшим Wi-Fi на первый SYN. */
    private class TimingOutSocket : Socket() {
        override fun connect(endpoint: java.net.SocketAddress, timeout: Int) = throw java.net.SocketTimeoutException("connect timed out")
    }

    private fun drain(server: ServerSocket, times: Int) = Executors.newSingleThreadExecutor().submit {
        repeat(times) { server.accept().use { it.getInputStream().readBytes() } }
    }

    @Test fun connectTimeoutIsRetriedOnceForAddressThatRecentlyDelivered() {
        ServerSocket(0).use { server ->
            val sockets = ArrayDeque<() -> Socket>()
            val retrying = LineSocketClient(log, socketFactory = { sockets.removeFirst()() })
            val done = drain(server, 2)
            sockets.addLast { Socket() }
            assertEquals(SendOutcome.DELIVERED, retrying.sendLineOutcome("127.0.0.1", server.localPort, "первая"))
            // второй раз первое соединение «зависает», повтор проходит
            sockets.addLast { TimingOutSocket() }
            sockets.addLast { Socket() }
            assertEquals(SendOutcome.DELIVERED, retrying.sendLineOutcome("127.0.0.1", server.localPort, "вторая"))
            done.get(5, TimeUnit.SECONDS)
            assertTrue(log.has("W/Socket send.connect_retry"))
            assertTrue(sockets.isEmpty())
        }
    }

    @Test fun connectTimeoutIsNotRetriedForAddressThatNeverDelivered() {
        var created = 0
        val c = LineSocketClient(log, socketFactory = { created++; TimingOutSocket() })
        assertEquals(SendOutcome.NOT_REACHED, c.sendLineOutcome("127.0.0.1", 9, "x"))
        assertEquals(1, created)
        assertFalse(log.has("send.connect_retry"))
    }

    @Test fun retryAlsoFailingGivesNotReachedAfterExactlyTwoAttempts() {
        ServerSocket(0).use { server ->
            val drained = drain(server, 1)
            var mode = "ok"
            var created = 0
            val c = LineSocketClient(log, socketFactory = { created++; if (mode == "ok") Socket() else TimingOutSocket() })
            assertEquals(SendOutcome.DELIVERED, c.sendLineOutcome("127.0.0.1", server.localPort, "ок"))
            drained.get(5, TimeUnit.SECONDS)
            mode = "timeout"
            created = 0
            assertEquals(SendOutcome.NOT_REACHED, c.sendLineOutcome("127.0.0.1", server.localPort, "x"))
            assertEquals(2, created)
        }
    }

    @Test fun retryWindowExpires() {
        ServerSocket(0).use { server ->
            val drained = drain(server, 1)
            var now = 0L
            var mode = "ok"
            var created = 0
            val c = LineSocketClient(log, socketFactory = { created++; if (mode == "ok") Socket() else TimingOutSocket() }, clock = { now })
            assertEquals(SendOutcome.DELIVERED, c.sendLineOutcome("127.0.0.1", server.localPort, "ок"))
            drained.get(5, TimeUnit.SECONDS)
            mode = "timeout"
            created = 0
            now = 6 * 60_000L
            assertEquals(SendOutcome.NOT_REACHED, c.sendLineOutcome("127.0.0.1", server.localPort, "x"))
            assertEquals(1, created)
        }
    }
}
