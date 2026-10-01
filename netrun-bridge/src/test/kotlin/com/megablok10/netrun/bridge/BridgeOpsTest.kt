package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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

/** Операции с ценностями, терминал и сессия по настоящему WebSocket (роль `test` — через `--test`, как у фейков). */
class BridgeOpsTest {
    @get:Rule val tmp = TemporaryFolder()

    private lateinit var store: DocStore
    private lateinit var server: BridgeServer
    private val clients = ArrayList<Client>()
    private val issued = ArrayList<IssuedTransfer>()

    @Before fun setUp() {
        store = DocStore.open(tmp.root.resolve("b.db").path)
        val cfg = BridgeConfig(port = 0, roleKeys = mapOf("world" to "kw", "master" to "km", "test" to "kt"), testMode = true)
        server = BridgeServer(store, cfg, ValueOps(store) { synchronized(issued) { issued.addAll(it) } })
        server.start()
        store.put("node", "node_07", 0, obj("tier" to "STANDARD", "lockdown_until" to 0L, "eddies" to 300L))
        store.put(
            "terminal", "t03", 0,
            obj("node" to "node_07", "label" to "стойка", "token_sha256" to VJ.sha256Hex("secret-token")),
        )
        store.put("runner", ValueOps.runnerDocId("KA"), 0, obj("key" to "KA", "callsign" to "A", "blocked" to false, "runs" to 1, "tutorial_done" to true))
        for ((id, owner, protectedFlag) in listOf(Triple("it_d1", "inbox:KA", true), Triple("it_d2", "inbox:KA", false), Triple("it_sh", "node:node_07", false))) {
            store.put(
                "item", id, 0,
                obj(
                    "owner" to owner, "kind" to "DAEMON", "payload" to "p", "protected" to protectedFlag,
                    "origin" to if (owner.startsWith("node")) "node:node_07" else "phone:KA",
                    "in_transfer" to null, "out_transfer" to null, "handover" to null,
                ),
            )
        }
    }

    @After fun tearDown() {
        clients.forEach { it.close() }
        server.stop()
        store.close()
    }

    private fun obj(vararg p: Pair<String, Any?>) = JsonObject(
        p.associate { (k, v) ->
            k to when (v) {
                null -> kotlinx.serialization.json.JsonNull
                is Long -> kotlinx.serialization.json.JsonPrimitive(v)
                is Int -> kotlinx.serialization.json.JsonPrimitive(v)
                is Boolean -> kotlinx.serialization.json.JsonPrimitive(v)
                else -> kotlinx.serialization.json.JsonPrimitive(v.toString())
            }
        },
    )

    private inner class Client(role: String) {
        private val inbox = LinkedBlockingQueue<JsonObject>()
        private var n = 0
        private val buf = StringBuilder()
        private val ws: WebSocket = HttpClient.newHttpClient().newWebSocketBuilder().buildAsync(
            URI("ws://127.0.0.1:${server.port}${BridgeServer.PATH}"),
            object : WebSocket.Listener {
                override fun onText(w: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                    buf.append(data)
                    if (last) { inbox.add(Json.parseToJsonElement(buf.toString()).jsonObject); buf.clear() }
                    w.request(1)
                    return null
                }
            },
        ).get(5, TimeUnit.SECONDS)

        init {
            clients.add(this)
            assertTrue(req("hello", """"proto":1,"role":"$role","client":"$role-1","key":"k${role[0]}"""").ok())
        }

        fun req(op: String, body: String = ""): JsonObject {
            val cid = "c${++n}"
            ws.sendText("""{"v":1,"cid":"$cid","op":"$op"${if (body.isEmpty()) "" else ",$body"}}""", true).get(5, TimeUnit.SECONDS)
            val r = inbox.poll(5, TimeUnit.SECONDS) ?: error("нет ответа")
            assertEquals(cid, r["re"]!!.jsonPrimitive.content)
            return r
        }

        fun close() { runCatching { ws.abort() } }
    }

    private fun JsonObject.ok() = this["ok"]!!.jsonPrimitive.content == "true"
    private fun JsonObject.code() = this["err"]!!.jsonObject["code"]!!.jsonPrimitive.content
    private fun JsonObject.str(k: String) = this[k]!!.jsonPrimitive.content
    private fun owner(id: String) = store.get("item", id)!!.data["owner"]!!.jsonPrimitive.content

    private fun submit(c: Client) = c.req(
        "op.submit_deck",
        """"rid":"enter:1","runner":"KA","callsign":"A","terminal":"t03","items":["it_d1","it_d2"],"protected":"it_d1"""",
    )

    @Test fun submitTakeFinishWithReplay() {
        val t = Client("test")
        val sub = submit(t)
        assertTrue(sub.toString(), sub.ok())
        assertEquals("false", sub.str("replayed"))
        val sid = sub.str("session")
        assertEquals("deck:$sid", owner("it_d2"))

        // повтор с тем же rid: тот же ответ, вторая сессия не создаётся
        val again = submit(t)
        assertEquals("true", again.str("replayed"))
        assertEquals(sid, again.str("session"))
        assertEquals(1, store.list("session").size)

        val w = Client("world")
        assertTrue(w.req("session.confirm", """"session":"$sid","terminal":"t03"""").ok())
        val take = w.req("op.take_from_node", """"rid":"take:$sid:it_sh","session":"$sid","node":"node_07","item":"it_sh"""")
        assertTrue(take.toString(), take.ok())
        assertEquals("deck:$sid", owner("it_sh"))
        // тот же rid с другими параметрами
        assertEquals("rid_mismatch", w.req("op.take_from_node", """"rid":"take:$sid:it_sh","session":"$sid","node":"node_07","eddies":5""").code())

        val fin = """"rid":"finish:$sid","session":"$sid","outcome":"clean","node":"node_07","disconnect":false,"moves":[{"item":"it_d2","to":"phone"},{"item":"it_sh","to":"phone"}]"""
        val done = w.req("run.finish", fin)
        assertTrue(done.toString(), done.ok())
        assertEquals("false", done.str("replayed"))
        assertEquals("closed", done["session"]!!.jsonObject["data"]!!.jsonObject.str("state"))
        assertEquals("outbox:KA", owner("it_sh"))
        val repeat = w.req("run.finish", fin)
        assertEquals("true", repeat.str("replayed"))
        synchronized(issued) { assertEquals(3, issued.size) } // защищённый + 2 предмета; повтор карточек не добавил
    }

    @Test fun domainErrorCarriesDocAndRoleIsChecked() {
        val w = Client("world")
        assertEquals("forbidden", w.req("op.submit_deck", """"rid":"r","runner":"KA","callsign":"A","terminal":"t03","items":["it_d1"],"protected":"it_d1"""").code())
        assertEquals("bad_request", w.req("op.leave_in_node", """"rid":"r"""").code())
        val m = Client("master")
        assertEquals("forbidden", m.req("terminal.auth", """"terminal":"t03","token":"secret-token"""").code())
        val bad = Client("test").req("op.leave_in_node", """"rid":"l1","session":"nope","node":"node_07","item":"it_sh"""")
        assertEquals("not_found", bad.code())
    }

    @Test fun terminalAuthAndBeat() {
        val w = Client("world")
        val ok = w.req("terminal.auth", """"terminal":"t03","token":"secret-token"""")
        assertTrue(ok.ok())
        assertEquals("t03", ok["terminal"]!!.jsonObject.str("id"))
        assertEquals("null", ok["session"].toString())
        assertEquals("bad_token", w.req("terminal.auth", """"terminal":"t03","token":"wrong"""").code())
        assertEquals("bad_token", w.req("terminal.auth", """"terminal":"t99","token":"secret-token"""").code())

        val before = store.get("terminal", "t03")!!
        val beat = w.req("terminal.beat", """"terminal":"t03","battery":80,"fps":72""")
        assertTrue(beat.toString(), beat.ok())
        val after = store.get("terminal", "t03")!!
        assertTrue(after.ver > before.ver)
        assertEquals("80", after.data["battery"]!!.jsonPrimitive.content)
        assertEquals("72", after.data["fps"]!!.jsonPrimitive.content)
        assertNotNull(after.data["beat_at"])
        assertEquals("not_found", w.req("terminal.beat", """"terminal":"t99"""").code())
        assertEquals("forbidden", Client("master").req("terminal.beat", """"terminal":"t03"""").code())
    }

    @Test fun commonPutRejectsPayoutAndOpRid() {
        val m = Client("master")
        assertEquals("value_field", m.req("put", """"type":"payout","id":"p1","ver":0,"data":{"eddies":5}""").code())
        assertEquals("value_field", m.req("put", """"type":"op_rid","id":"x1","ver":0,"data":{}""").code())
        assertFalse(store.list("payout").isNotEmpty())
    }

    @Test fun abortFromPendingReturnsDeck() {
        val t = Client("test")
        val sid = submit(t).str("session")
        val r = Client("master").req("session.abort", """"session":"$sid","reason":"отказ"""")
        assertTrue(r.toString(), r.ok())
        assertEquals("aborted", r["session"]!!.jsonObject["data"]!!.jsonObject.str("outcome"))
        assertEquals("outbox:KA", owner("it_d1"))
    }
}
