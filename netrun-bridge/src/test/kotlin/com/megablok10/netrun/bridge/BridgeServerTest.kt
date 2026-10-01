package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.net.URI
import java.net.http.HttpClient
import java.net.http.WebSocket
import java.util.concurrent.CompletionStage
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** Настоящий клиент WebSocket (JDK `java.net.http`, не та библиотека, что у сервера) против настоящего сервера. */
class BridgeServerTest {
    @get:Rule val tmp = TemporaryFolder()

    private lateinit var store: DocStore
    private lateinit var server: BridgeServer
    private val clients = ArrayList<Client>()

    @Before fun setUp() {
        store = DocStore.open(tmp.root.resolve("b.db").path)
        server = BridgeServer(store, config())
        server.start()
    }

    @After fun tearDown() {
        clients.forEach { it.close() }
        server.stop()
        store.close()
    }

    private fun config(idle: Long = 30_000) = BridgeConfig(
        port = 0, roleKeys = mapOf("world" to "kw", "master" to "km", "test" to "kt"), testMode = false,
        idleTimeoutMs = idle, worldPub = "PUB",
    )

    private inner class Client(path: String = BridgeServer.PATH) {
        val inbox = LinkedBlockingQueue<JsonObject>()
        @Volatile var closeCode: Int? = null
        private val buf = StringBuilder()
        private var n = 0
        val ws: WebSocket = HttpClient.newHttpClient().newWebSocketBuilder()
            .buildAsync(
                URI("ws://127.0.0.1:${server.port}$path"),
                object : WebSocket.Listener {
                    override fun onText(w: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                        buf.append(data)
                        if (last) { inbox.add(Json.parseToJsonElement(buf.toString()).jsonObject); buf.clear() }
                        w.request(1)
                        return null
                    }
                    override fun onClose(w: WebSocket, statusCode: Int, reason: String?): CompletionStage<*>? {
                        closeCode = statusCode
                        return null
                    }
                },
            ).get(5, TimeUnit.SECONDS)
        init { clients.add(this) }

        fun send(json: String) { ws.sendText(json, true).get(5, TimeUnit.SECONDS) }
        fun next(): JsonObject = inbox.poll(5, TimeUnit.SECONDS) ?: error("нет сообщения за 5 с")
        fun req(op: String, body: String = ""): JsonObject {
            val cid = "c${++n}"
            send("""{"v":1,"cid":"$cid","op":"$op"${if (body.isEmpty()) "" else ",$body"}}""")
            val r = next()
            assertEquals(cid, r["re"]?.jsonPrimitive?.content)
            return r
        }
        fun hello(role: String = "master", key: String = "k" + role[0]) =
            req("hello", """"proto":1,"role":"$role","client":"$role-1","key":"$key"""")
        fun close() { runCatching { ws.abort() } }
    }

    private fun JsonObject.ok() = this["ok"]!!.jsonPrimitive.content == "true"
    private fun JsonObject.code() = this["err"]!!.jsonObject["code"]!!.jsonPrimitive.content
    private fun JsonObject.ver() = this["doc"]!!.jsonObject["ver"]!!.jsonPrimitive.content.toLong()

    @Test fun helloRolesAndKeys() {
        val c = Client()
        assertEquals("unauthorized", c.req("get", """"type":"node","id":"n"""").code())
        val h = c.hello()
        assertTrue(h.ok())
        assertEquals("PUB", h["world_pub"]!!.jsonPrimitive.content)
        assertEquals("bad_request", c.hello().code()) // второй hello

        val bad = Client()
        assertEquals("unauthorized", bad.hello("master", "nope").code())
        val test = Client()
        assertEquals("unauthorized", test.hello("test").code()) // без --test
        val v = Client()
        assertEquals("unsupported_version", v.req("hello", """"proto":9,"role":"master","client":"x","key":"km"""").code())
    }

    @Test fun getListPutDelete() {
        val c = Client(); c.hello()
        assertEquals("not_found", c.req("get", """"type":"terminal","id":"t03"""").code())
        val created = c.req("put", """"type":"terminal","id":"t03","ver":0,"data":{"label":"A"}""")
        assertEquals(1L, created.ver())
        assertEquals("exists", c.req("put", """"type":"terminal","id":"t03","ver":0,"data":{}""").code())
        val upd = c.req("put", """"type":"terminal","id":"t03","ver":1,"data":{"label":"B"}""")
        assertEquals(2L, upd.ver())
        assertEquals(2L, c.req("get", """"type":"terminal","id":"t03"""").ver())
        val l = c.req("list", """"type":"terminal"""")
        assertEquals(1, l["docs"]!!.jsonArray.size)
        assertEquals("bad_request", c.req("list", """"type":"BAD!"""").code())
        assertEquals("version_conflict", c.req("del", """"type":"terminal","id":"t03","ver":1""").code())
        assertTrue(c.req("del", """"type":"terminal","id":"t03","ver":2""").ok())
        assertEquals("not_found", c.req("get", """"type":"terminal","id":"t03"""").code())
    }

    @Test fun staleVersionRejectedWithCurrentDoc() {
        val c = Client(); c.hello()
        c.req("put", """"type":"node","id":"n1","ver":0,"data":{"a":1}""")
        c.req("put", """"type":"node","id":"n1","ver":1,"data":{"a":2}""")
        val r = c.req("put", """"type":"node","id":"n1","ver":1,"data":{"a":3}""")
        assertFalse(r.ok())
        assertEquals("version_conflict", r.code())
        assertEquals("2", r["err"]!!.jsonObject["doc"]!!.jsonObject["data"]!!.jsonObject["a"]!!.jsonPrimitive.content)
        assertEquals(2L, store.get("node", "n1")!!.ver)
    }

    @Test fun twoSubscribersSeeOneChange() {
        val a = Client(); a.hello()
        val b = Client(); b.hello("world")
        val w = Client(); w.hello()
        w.req("put", """"type":"node","id":"n1","ver":0,"data":{"x":1}""")
        val snapA = a.req("sub", """"types":["node"]""")
        val snapB = b.req("sub", """"types":["node","alert"]""")
        assertEquals(1, snapA["docs"]!!.jsonArray.size)
        assertEquals(snapA["seq"], snapB["seq"])

        w.req("put", """"type":"node","id":"n1","ver":1,"data":{"x":2}""")
        w.req("put", """"type":"terminal","id":"t1","ver":0,"data":{}""") // не подписаны — пуша нет
        for (c in listOf(a, b)) {
            val p = c.next()
            assertEquals("chg", p["push"]!!.jsonPrimitive.content)
            assertEquals(2L, p["doc"]!!.jsonObject["ver"]!!.jsonPrimitive.content.toLong())
            assertEquals("true", p["last"]!!.jsonPrimitive.content)
            assertEquals(snapA["seq"]!!.jsonPrimitive.content.toLong() + 1, p["seq"]!!.jsonPrimitive.content.toLong())
        }
        w.req("del", """"type":"node","id":"n1","ver":2""")
        val del = a.next()
        assertEquals("true", del["deleted"]!!.jsonPrimitive.content)
        assertNull(a.inbox.poll(200, TimeUnit.MILLISECONDS)) // пуша про terminal не было

        a.req("unsub", """"types":["node"]""")
        w.req("put", """"type":"node","id":"n2","ver":0,"data":{}""")
        assertNull(a.inbox.poll(300, TimeUnit.MILLISECONDS))
        assertEquals("chg", b.next()["push"]!!.jsonPrimitive.content)
    }

    @Test fun transactionArrivesAsBatchWithLastFlag() {
        val a = Client(); a.hello()
        a.req("sub", """"types":["item","deck"]""")
        store.transaction { tx ->
            tx.put("item", "it_1", 0, JsonObject(emptyMap()))
            tx.put("deck", "s_1", 0, JsonObject(emptyMap()))
        }
        val p1 = a.next(); val p2 = a.next()
        assertEquals(p1["seq"], p2["seq"])
        assertEquals("false", p1["last"]!!.jsonPrimitive.content)
        assertEquals("true", p2["last"]!!.jsonPrimitive.content)
    }

    @Test fun rolesAndValueFields() {
        val w = Client(); w.hello("world")
        assertEquals("forbidden", w.req("put", """"type":"terminal","id":"t","ver":0,"data":{}""").code())
        assertEquals("forbidden", w.req("put", """"type":"item","id":"it_1","ver":0,"data":{}""").code())
        assertEquals("value_field", w.req("put", """"type":"session","id":"s_1","ver":0,"data":{}""").code())
        store.put("session", "s_1", 0, Json.parseToJsonElement("""{"state":"active","world":{"trace":0}}""").jsonObject)
        assertTrue(w.req("put", """"type":"session","id":"s_1","ver":1,"data":{"state":"active","world":{"trace":5}}""").ok())
        assertEquals("value_field", w.req("put", """"type":"session","id":"s_1","ver":2,"data":{"state":"closed","world":{}}""").code())
        assertEquals("value_field", w.req("del", """"type":"session","id":"s_1","ver":2""").code())

        val m = Client(); m.hello("master")
        assertTrue(m.req("put", """"type":"node","id":"n","ver":0,"data":{"eddies":300}""").ok())
        assertEquals("value_field", m.req("put", """"type":"node","id":"n","ver":1,"data":{"eddies":0}""").code())
        assertTrue(m.req("put", """"type":"node","id":"n","ver":1,"data":{"eddies":300,"tier":"STANDARD"}""").ok())
        assertEquals("value_field", m.req("put", """"type":"item","id":"it_1","ver":0,"data":{}""").code())
        assertEquals("value_field", m.req("del", """"type":"item","id":"it_1","ver":1""").code())
    }

    @Test fun valueOpsRolesAndUnknownOp() {
        val m = Client(); m.hello("master")
        assertEquals("not_found", m.req("op.take_from_node", """"rid":"take:s:i","session":"s","node":"n","item":"i"""").code())
        assertEquals("bad_request", m.req("op.take_from_node").code())
        assertEquals("forbidden", m.req("op.submit_deck", """"rid":"r","runner":"k","callsign":"c","terminal":"t","items":["i"],"protected":"i"""").code())
        assertEquals("forbidden", m.req("session.confirm", """"session":"s","terminal":"t"""").code())
        assertEquals("bad_request", m.req("frobnicate").code())
    }

    @Test fun badFramesAndPath() {
        val c = Client(); c.hello()
        c.send("не json")
        val r = c.next()
        assertEquals("bad_request", r.code())
        assertNull(r["re"])
        c.ws.sendBinary(java.nio.ByteBuffer.wrap(byteArrayOf(1)), true)
        assertEquals("bad_request", c.next().code())
        val deadline = System.currentTimeMillis() + 5000
        while (c.closeCode == null && System.currentTimeMillis() < deadline) Thread.sleep(20)
        assertEquals(1003, c.closeCode)

        val wrong = Client("/other")
        val d2 = System.currentTimeMillis() + 5000
        while (wrong.closeCode == null && System.currentTimeMillis() < d2) Thread.sleep(20)
        assertEquals(1008, wrong.closeCode)
    }

    @Test fun silentConnectionIsClosed() {
        server.stop()
        server = BridgeServer(store, config(idle = 600))
        server.start()
        val c = Client(); c.hello()
        val deadline = System.currentTimeMillis() + 5000
        while (c.closeCode == null && System.currentTimeMillis() < deadline) Thread.sleep(50)
        assertEquals(1001, c.closeCode)
    }
}
