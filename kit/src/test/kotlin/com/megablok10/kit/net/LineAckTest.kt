package com.megablok10.kit.net

import com.megablok10.kit.log.RecordingLog
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ответ получателя (docs/refactor-plan.md, D2) на настоящих сокетах: «ок» только после обработки и только от того ключа, что
 * ждали; «не мне» — строка не обработана; без ответа — могло дойти. Каждый исход — то, что потом решает судьбу денег.
 */
class LineAckTest {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val log = RecordingLog()
    private val handled = LinkedBlockingQueue<String>()
    private val heard = LinkedBlockingQueue<String>()
    private val outcomes = LinkedBlockingQueue<String>()
    private val client = LineSocketClient(log, ackTimeoutMs = 1500) { _, _, outcome, by -> outcomes += "$outcome:$by" }

    private fun server(me: String? = "bob", handleTimeoutMs: Long = 3_000) = LineServer(
        routes = listOf(
            LineRoute("chat", { l -> l.removePrefix("CHAT:").takeIf { it != l } }) { body ->
                when (body) {
                    "boom" -> error("обработчик упал")
                    "slow" -> delay(1_000)
                }
                handled += body
            },
        ),
        log = log, tag = "ChatServer", identityKey = { me }, handleTimeoutMs = handleTimeoutMs,
        onHeard = { key, host, port -> heard += "$key@$host:$port" },
    ).also { it.start(scope) }

    private fun send(s: LineServer, body: String, to: String = "bob", expect: String = to) =
        client.sendLineOutcome("127.0.0.1", s.port, LineEnvelope(to, "alice", 47100, "CHAT:$body").encode(), expectAckFrom = expect)

    @After fun tearDown() { scope.cancel() }

    @Test fun okComesAfterTheLineWasHandled() {
        val s = server()
        assertEquals(SendOutcome.DELIVERED, send(s, "привет"))
        // обработчик завершился ДО ответа: строка уже здесь, без ожидания
        assertEquals("привет", handled.poll())
        assertEquals("DELIVERED:bob", outcomes.poll(1, TimeUnit.SECONDS))
        assertEquals("alice@127.0.0.1:47100", heard.poll(1, TimeUnit.SECONDS))
    }

    @Test fun lineForAnotherPlayerIsNotHandledAndSaysWho() {
        val s = server(me = "bob")
        assertEquals(SendOutcome.NOT_REACHED, send(s, "деньги", to = "carol"))
        assertEquals("NOT_REACHED:bob", outcomes.poll(1, TimeUnit.SECONDS))
        assertNull("чужую строку не обработали", handled.poll(300, TimeUnit.MILLISECONDS))
        assertTrue(log.has("W/ChatServer server.not_for_me"))
    }

    @Test fun withoutIdentityTheLineIsRejectedNotHandled() {
        val s = server(me = null)
        assertEquals(SendOutcome.NOT_REACHED, send(s, "x"))
        assertNull(handled.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test fun unknownInnerLineIsRejected() {
        val s = server()
        val outcome = client.sendLineOutcome("127.0.0.1", s.port, LineEnvelope("bob", "alice", 47100, "MB10CHAT:v9:?").encode(), expectAckFrom = "bob")
        assertEquals(SendOutcome.NOT_REACHED, outcome)
    }

    @Test fun failingHandlerGivesNoAnswerSoItMayHaveArrived() {
        val s = server()
        assertEquals(SendOutcome.UNKNOWN, send(s, "boom"))
        assertTrue(log.has("W/Socket send.no_ack"))
        assertEquals("сервер жив", SendOutcome.DELIVERED, send(s, "дальше"))
    }

    @Test fun handlerSlowerThanTheLimitGivesNoAnswerButIsNotAbandoned() {
        val s = server(handleTimeoutMs = 200)
        assertEquals(SendOutcome.UNKNOWN, send(s, "slow"))
        assertEquals("обработка доведена до конца", "slow", handled.poll(3, TimeUnit.SECONDS))
    }

    @Test fun okFromAnotherKeyIsNotDelivery() {
        val s = server(me = "bob")
        // конверт «для bob», но ждём ответа от carol (адрес считали её): ok от bob — не доставка carol
        assertEquals(SendOutcome.UNKNOWN, send(s, "x", to = "bob", expect = "carol"))
    }

    @Test fun oldReceiverWithoutAnswerMeansItMayHaveArrived() {
        // получатель на старой версии: читает строку и молча закрывает соединение
        ServerSocket(0).use { old ->
            val done = Executors.newSingleThreadExecutor().submit { old.accept().use { it.getInputStream().bufferedReader().readLine() } }
            val outcome = client.sendLineOutcome("127.0.0.1", old.localPort, LineEnvelope("bob", "alice", 1, "CHAT:x").encode(), expectAckFrom = "bob")
            done.get(5, TimeUnit.SECONDS)
            assertEquals(SendOutcome.UNKNOWN, outcome)
        }
    }

    @Test fun lineWithoutEnvelopeFromAnOldSenderIsStillHandled() {
        val s = server()
        assertEquals(SendOutcome.DELIVERED, client.sendLineOutcome("127.0.0.1", s.port, "CHAT:по-старому"))
        assertEquals("по-старому", handled.poll(3, TimeUnit.SECONDS))
    }

    @Test fun envelopeRoundTripAndBadEnvelopes() {
        val e = LineEnvelope("to/+=", "from", 47100, "MB10CHAT:v1:DM:a:b:c")
        assertEquals(e, LineEnvelope.decode(e.encode()))
        assertNull(LineEnvelope.decode("MB10TO:v2:a:b:1:x"))
        assertNull(LineEnvelope.decode("MB10TO:v1::b:1:x"))
        assertNull(LineEnvelope.decode("MB10TO:v1:a:b:порт:x"))
        assertEquals(LineAck(LineAck.Status.WRONG, "k"), LineAck.decode("MB10ACK:v1:wrong:k"))
        assertNull(LineAck.decode("MB10ACK:v1:maybe:k"))
    }
}
