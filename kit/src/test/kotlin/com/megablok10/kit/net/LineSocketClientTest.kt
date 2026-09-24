package com.megablok10.kit.net

import com.megablok10.kit.log.RecordingLog
import java.net.ServerSocket
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
}
