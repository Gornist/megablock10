package com.megablok10.kit.net

import com.megablok10.kit.log.RecordingLog
import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сервер строк на настоящих сокетах localhost: маршруты, мусор, молчащие клиенты, сбои обработчиков. */
class LineServerTest {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val log = RecordingLog()
    private val events = LinkedBlockingQueue<String>()
    private val client = LineSocketClient()

    private fun server(maxLine: Int = 1024, readTimeoutMs: Int = 500, onUnknown: (String) -> Unit = { events += "unknown:$it" }) = LineServer(
        routes = listOf(
            LineRoute("chat", { l -> l.removePrefix("CHAT:").takeIf { it != l } }) { events += "chat:$it" },
            LineRoute("call", { l -> l.removePrefix("CALL:").takeIf { it != l } }) { if (it == "boom") error("обработчик упал") else events += "call:$it" },
        ),
        onUnrecognized = onUnknown, log = log, tag = "ChatServer", maxLineChars = maxLine, readTimeoutMs = readTimeoutMs,
    ).also { it.start(scope) }

    private fun next(): String? = events.poll(5, TimeUnit.SECONDS)

    /** Соединения обрабатываются параллельно: запись в журнал о «соседнем» соединении может прийти чуть позже события. */
    private fun awaitLog(fragment: String): Boolean {
        val deadline = System.currentTimeMillis() + 5_000
        while (!log.has(fragment) && System.currentTimeMillis() < deadline) Thread.sleep(20)
        return log.has(fragment)
    }

    @After fun tearDown() { scope.cancel() }

    @Test fun routesLinesByProtocolAndReportsPort() {
        val s = server()
        assertTrue(s.port > 0)
        assertEquals(SendOutcome.DELIVERED, client.sendLineOutcome("127.0.0.1", s.port, "CHAT:привет"))
        assertEquals("chat:привет", next())
        client.sendLine("127.0.0.1", s.port, "CALL:offer")
        assertEquals("call:offer", next())
        assertTrue(log.has("I/ChatServer server.listen port=${s.port}"))
        assertTrue(log.has("server.recv from=127.0.0.1 kind=chat chars=11"))
        s.stop()
        assertEquals(-1, s.port)
    }

    @Test fun unknownLineGoesToUnrecognized() {
        val s = server()
        client.sendLine("127.0.0.1", s.port, "MB10CHAT:v9:что-то")
        assertEquals("unknown:MB10CHAT:v9:что-то", next())
        assertTrue(log.has("W/ChatServer server.incompatible_line"))
        s.stop()
    }

    @Test fun oversizeLineIsDroppedAndServerKeepsWorking() {
        val s = server(maxLine = 16)
        client.sendLine("127.0.0.1", s.port, "CHAT:" + "x".repeat(100))
        client.sendLine("127.0.0.1", s.port, "CHAT:ок")
        assertEquals("chat:ок", next())
        assertTrue(awaitLog("W/ChatServer server.empty_or_oversize"))
        s.stop()
    }

    @Test fun silentClientTimesOutWithoutBlockingOthers() {
        val s = server(readTimeoutMs = 300)
        Socket("127.0.0.1", s.port).use { silent ->
            client.sendLine("127.0.0.1", s.port, "CHAT:пока другой молчит")
            assertEquals("chat:пока другой молчит", next())
            // молчащий клиент отваливается по таймауту чтения — сервер закрывает его соединение
            assertTrue(awaitLog("входящее соединение отброшено: SocketTimeoutException"))
            assertEquals(-1, silent.getInputStream().read())
        }
        client.sendLine("127.0.0.1", s.port, "CHAT:после")
        assertEquals("chat:после", next())
        s.stop()
    }

    @Test fun failingHandlerDoesNotKillServer() {
        val s = server()
        client.sendLine("127.0.0.1", s.port, "CALL:boom")
        client.sendLine("127.0.0.1", s.port, "CALL:дальше")
        assertEquals("call:дальше", next())
        assertTrue(awaitLog("входящее соединение отброшено: IllegalStateException"))
        assertNull(events.poll(200, TimeUnit.MILLISECONDS))
        s.stop()
    }
}
