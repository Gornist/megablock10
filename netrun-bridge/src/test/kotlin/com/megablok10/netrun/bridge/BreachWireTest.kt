package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URI
import java.net.http.HttpClient
import java.net.http.WebSocket
import java.util.concurrent.CompletionStage
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** `run.breach` по настоящему WebSocket (роль `world`): разбор полей, ответ по протоколу, повтор с `replayed`, отказ `cooldown`. */
class BreachWireTest {
    private val f = BreachFixture()
    private val server = BridgeServer(
        f.store, BridgeConfig(port = 0, roleKeys = mapOf("world" to "kw", "master" to "km")), f.ops,
    ).also { it.start() }
    private val inbox = LinkedBlockingQueue<JsonObject>()
    private var n = 0
    private val ws: WebSocket = HttpClient.newHttpClient().newWebSocketBuilder().buildAsync(
        URI("ws://127.0.0.1:${server.port}${BridgeServer.PATH}"),
        object : WebSocket.Listener {
            private val buf = StringBuilder()
            override fun onText(w: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                buf.append(data)
                if (last) { inbox.add(Json.parseToJsonElement(buf.toString()).jsonObject); buf.clear() }
                w.request(1)
                return null
            }
        },
    ).get(5, TimeUnit.SECONDS)

    @After fun tearDown() {
        runCatching { ws.abort() }
        server.stop()
        f.store.close()
    }

    private fun req(op: String, body: String): JsonObject {
        val cid = "c${++n}"
        ws.sendText("""{"v":1,"cid":"$cid","op":"$op",$body}""", true).get(5, TimeUnit.SECONDS)
        val r = inbox.poll(5, TimeUnit.SECONDS) ?: error("нет ответа")
        assertEquals(cid, r["re"]!!.jsonPrimitive.content)
        return r
    }

    @Test fun breachOverTheWire() {
        assertTrue(req("hello", """"proto":1,"role":"world","client":"world-main","key":"kw"""").getValue("ok").jsonPrimitive.content == "true")
        val sid = f.enterA()
        val body = """"rid":"breach:$sid:1","session":"$sid","node":"node_07","n":1,"tier":"HARD","selected":["it_ex","it_miner"],""" +
            """"matched":["it_ex"],"active":["GHOST"],"vaults":["v_sh1","v_sh2"],"open_s":60"""
        val r = req("run.breach", body)
        assertEquals(r.toString(), "true", r["ok"]!!.jsonPrimitive.content)
        assertEquals("false", r["replayed"]!!.jsonPrimitive.content)
        assertEquals("PARTIAL", r["outcome"]!!.jsonPrimitive.content)
        assertEquals(1, r["opened"]!!.toString().split("v_sh1").size - 1)
        val again = req("run.breach", body)
        assertEquals("true", again["replayed"]!!.jsonPrimitive.content)
        val second = req("run.breach", body.replace("breach:$sid:1", "breach:$sid:2").replace("\"n\":1", "\"n\":2"))
        assertEquals("cooldown", second["err"]!!.jsonObject["code"]!!.jsonPrimitive.content)
        val missing = req("run.breach", """"rid":"x","session":"$sid"""")
        assertEquals("bad_request", missing["err"]!!.jsonObject["code"]!!.jsonPrimitive.content)
    }
}
