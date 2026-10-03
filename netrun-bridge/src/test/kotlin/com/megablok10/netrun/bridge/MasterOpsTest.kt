package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

/** Инструменты мастера (протокол, раздел 6a) по настоящему WebSocket; время — ручное, правила — ручным `tick`. */
class MasterOpsTest {
    @get:Rule val tmp = TemporaryFolder()

    private var now = 1_000_000L
    private lateinit var store: DocStore
    private lateinit var server: BridgeServer
    private lateinit var master: MasterOps
    private lateinit var rules: RuleEngine
    private val clients = ArrayList<Client>()

    @Before fun setUp() {
        store = DocStore.open(tmp.root.resolve("b.db").path) { now }
        master = MasterOps(store) { now }
        val cfg = BridgeConfig(port = 0, roleKeys = mapOf("world" to "kw", "master" to "km", "test" to "kt"), testMode = true)
        server = BridgeServer(store, cfg, ValueOps(store, { now }), master = master)
        server.start()
        rules = RuleEngine(store, { now })
        MasterRules(rules, master).register()
        store.put("settings", "global", 0, obj("world_pub" to "WP"))
        store.put("node", "node_07", 0, obj("tier" to "STANDARD", "lockdown_until" to 5_000_000L, "eddies" to 300L))
        store.put("node", "node_08", 0, obj("tier" to "STANDARD", "lockdown_until" to 0L, "eddies" to 0L))
    }

    @After fun tearDown() {
        clients.forEach { it.close() }
        rules.close()
        server.stop()
        store.close()
    }

    private fun obj(vararg p: Pair<String, Any?>) = JsonObject(
        p.associate { (k, v) -> k to (if (v is Number) JsonPrimitive(v) else if (v is Boolean) JsonPrimitive(v) else JsonPrimitive(v.toString())) },
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
    private fun data(type: String, id: String) = store.get(type, id)!!.data
    private fun flag(type: String, id: String, k: String) = data(type, id)[k]?.jsonPrimitive?.content

    @Test fun pauseWholeNetAndOneNode() {
        val m = Client("master")
        assertTrue(m.req("master.pause", """"on":true""").ok())
        assertEquals("true", flag("settings", "global", "paused"))
        assertEquals("WP", flag("settings", "global", "world_pub")) // чужие поля настроек целы
        assertTrue(MasterOps.isPaused(store, "node_07"))
        assertTrue(m.req("master.pause", """"on":false""").ok())
        assertFalse(MasterOps.isPaused(store, "node_07"))

        assertTrue(m.req("master.pause", """"on":true,"node":"node_08"""").ok())
        assertTrue(MasterOps.isPaused(store, "node_08"))
        assertFalse(MasterOps.isPaused(store, "node_07"))
        assertEquals("not_found", m.req("master.pause", """"on":true,"node":"node_99"""").code())
        assertEquals("bad_request", m.req("master.pause", """"node":"node_08"""").code())
    }

    @Test fun stockAndUnstockNodeOverTheWire() {
        val m = Client("master")
        val body = """"rid":"st1","node":"node_08","items":[{"kind":"DAEMON","payload":"p-x"}],"eddies":40"""
        val r = m.req("master.stock_node", body)
        assertTrue(r.toString(), r.ok())
        assertEquals("false", r.str("replayed"))
        assertEquals("40", flag("node", "node_08", "eddies"))
        val id = r["items"]!!.jsonArray[0].jsonPrimitive.content
        assertEquals("node:node_08", flag("item", id, "owner"))
        assertEquals("true", m.req("master.stock_node", body).str("replayed"))
        assertEquals("rid_mismatch", m.req("master.stock_node", """"rid":"st1","node":"node_08","items":[],"eddies":1""").code())
        assertEquals("forbidden", Client("world").req("master.stock_node", body).code())
        assertTrue(m.req("master.unstock_node", """"rid":"un1","node":"node_08","items":["$id"],"eddies":10""").ok())
        assertEquals("burned:master", flag("item", id, "owner"))
        assertEquals("30", flag("node", "node_08", "eddies"))
    }

    @Test fun venueLinkSwitch() {
        val m = Client("master")
        assertTrue(MasterOps.venueLinkOn(store)) // по умолчанию связь есть
        assertTrue(m.req("master.link", """"on":false""").ok())
        assertFalse(MasterOps.venueLinkOn(store))
        assertTrue(m.req("master.link", """"on":true""").ok())
        assertTrue(MasterOps.venueLinkOn(store))
    }

    @Test fun nonMasterIsRefused() {
        val w = Client("world")
        for ((op, body) in listOf(
            "master.pause" to """"on":true""", "master.link" to """"on":false""",
            "master.goal" to """"node":"node_07","kind":"open","in_s":5""", "master.goal_clear" to """"node":"node_07"""",
            "master.decide" to """"req":"x","decision":"approve"""", "master.template_apply" to """"template":"t"""",
            "master.reply" to """"query":"q","mid":"m","text":"t"""",
        )) assertEquals(op, "forbidden", w.req(op, body).code())
        assertFalse(store.get("settings", "global")!!.data.containsKey("paused"))
        assertEquals("bad_request", Client("master").req("master.nope").code())
    }

    @Test fun goalOpenAppliesAtDeadlineAndFreezesOnPause() {
        val m = Client("master")
        assertTrue(m.req("master.goal", """"node":"node_07","kind":"open","in_s":600""").ok())
        assertEquals("open", (data("node_cfg", "node_07")["goal"] as JsonObject).str("kind"))
        assertEquals("bad_request", m.req("master.goal", """"node":"node_07","kind":"open"""").code())

        now += 300_000; rules.tick()
        assertEquals("5000000", flag("node", "node_07", "lockdown_until")) // срок не наступил
        assertTrue(m.req("master.pause", """"on":true,"node":"node_07"""").ok())
        now += 400_000; rules.tick()
        assertEquals("5000000", flag("node", "node_07", "lockdown_until")) // на паузе цель не срабатывает
        assertTrue(m.req("master.pause", """"on":false,"node":"node_07"""").ok())
        // срок сдвинут на 400 с паузы: осталось 300 с
        assertEquals(1_000_000L + 600_000 + 400_000, ((data("node_cfg", "node_07")["goal"] as JsonObject)["deadline"] as JsonPrimitive).content.toLong())
        now += 299_000; rules.tick()
        assertEquals("5000000", flag("node", "node_07", "lockdown_until"))
        now += 2_000; rules.tick()
        assertEquals("0", flag("node", "node_07", "lockdown_until"))
        assertEquals("true", (data("node_cfg", "node_07")["goal"] as JsonObject).str("done"))
        assertEquals("300", flag("node", "node_07", "eddies")) // ценности автоматика не трогает

        assertTrue(m.req("master.goal_clear", """"node":"node_07"""").ok())
        assertFalse(data("node_cfg", "node_07").containsKey("goal"))
    }

    @Test fun gateOffIsAutoAndOnWaitsForMasterDecision() {
        val w = Client("world")
        val auto = w.req("master.gate", """"kind":"flatline","ref":"s_1","node":"node_07","summary":"флэтлайн"""")
        assertEquals("auto", auto.str("mode"))
        assertEquals("approve", auto.str("decision"))
        assertTrue(store.list("master_req").isEmpty())

        val m = Client("master")
        store.put("settings", "global", store.get("settings", "global")!!.ver, JsonObject(data("settings", "global") + obj("await_flatline" to 1, "await_timeout_s" to 30)))
        val wait = w.req("master.gate", """"kind":"flatline","ref":"s_1","node":"node_07","summary":"флэтлайн Призрак"""")
        assertEquals("wait", wait.str("mode"))
        assertEquals("flatline:s_1", wait["req"]!!.jsonObject.str("id"))
        assertEquals(1, store.list("alert").count { it.data["kind"]!!.jsonPrimitive.content == "master_request" })
        // повтор не плодит документов и тревог
        assertEquals("wait", w.req("master.gate", """"kind":"flatline","ref":"s_1","summary":"x"""").str("mode"))
        assertEquals(1, store.list("master_req").size)
        assertEquals(1, store.list("alert").size)

        assertEquals("bad_request", m.req("master.decide", """"req":"flatline:s_1","decision":"maybe"""").code())
        assertEquals("not_found", m.req("master.decide", """"req":"flatline:zz","decision":"deny"""").code())
        val dec = m.req("master.decide", """"req":"flatline:s_1","decision":"deny"""")
        assertTrue(dec.toString(), dec.ok())
        assertEquals("master", flag("master_req", "flatline:s_1", "decided_by"))
        val after = w.req("master.gate", """"kind":"flatline","ref":"s_1","summary":"x"""")
        assertEquals("decided", after.str("mode"))
        assertEquals("deny", after.str("decision"))
        // то же решение — идемпотентно, обратное — req_state с документом
        assertTrue(m.req("master.decide", """"req":"flatline:s_1","decision":"deny"""").ok())
        val flip = m.req("master.decide", """"req":"flatline:s_1","decision":"approve"""")
        assertEquals("req_state", flip.code())
        assertEquals("deny", flip["err"]!!.jsonObject["doc"]!!.jsonObject["data"]!!.jsonObject.str("decision"))
    }

    @Test fun gateTimeoutAppliesDefaultAction() {
        val m = Client("master")
        store.put(
            "settings", "global", store.get("settings", "global")!!.ver,
            JsonObject(data("settings", "global") + obj("await_flatline" to 1, "await_timeout_s" to 30, "await_default_flatline" to "deny")),
        )
        val w = Client("world")
        assertEquals("wait", w.req("master.gate", """"kind":"flatline","ref":"s_2","summary":"ф"""").str("mode"))
        now += 29_000; rules.tick()
        assertEquals("pending", flag("master_req", "flatline:s_2", "state"))
        now += 2_000; rules.tick()
        assertEquals("timeout", flag("master_req", "flatline:s_2", "decided_by"))
        assertEquals("deny", flag("master_req", "flatline:s_2", "decision"))
        // мастер опоздал: «разрешить» уже невозможно
        assertEquals("req_state", m.req("master.decide", """"req":"flatline:s_2","decision":"approve"""").code())
        // даже без тика таймаут применяется при обращении (gate / decide)
        assertEquals("wait", w.req("master.gate", """"kind":"flatline","ref":"s_3","summary":"ф"""").str("mode"))
        now += 31_000
        val g = w.req("master.gate", """"kind":"flatline","ref":"s_3","summary":"ф"""")
        assertEquals("decided", g.str("mode"))
        assertEquals("deny", g.str("decision"))
    }

    @Test fun lockdownGoalWaitsForMasterThenApplies() {
        val m = Client("master")
        store.put(
            "settings", "global", store.get("settings", "global")!!.ver,
            JsonObject(data("settings", "global") + obj("await_lockdown" to 1, "await_timeout_s" to 100)),
        )
        assertTrue(m.req("master.goal", """"node":"node_08","kind":"lockdown","value":120,"in_s":10""").ok())
        now += 11_000; rules.tick()
        assertEquals("0", flag("node", "node_08", "lockdown_until")) // ждём мастера
        assertEquals(1, store.list("master_req").size)
        val reqId = store.list("master_req").single().id
        now += 1_000; rules.tick()
        assertEquals(1, store.list("master_req").size) // повторный тик не плодит запросов
        assertTrue(m.req("master.decide", """"req":"$reqId","decision":"approve"""").ok())
        now += 1_000; rules.tick()
        assertEquals((now + 120_000).toString(), flag("node", "node_08", "lockdown_until"))
        assertEquals("applied", (data("node_cfg", "node_08")["goal"] as JsonObject).str("result"))
    }

    @Test fun lockdownGoalDeniedByTimeoutDefault() {
        val m = Client("master")
        store.put(
            "settings", "global", store.get("settings", "global")!!.ver,
            JsonObject(data("settings", "global") + obj("await_lockdown" to 1, "await_timeout_s" to 20, "await_default_lockdown" to "deny")),
        )
        assertTrue(m.req("master.goal", """"node":"node_08","kind":"lockdown","in_s":5""").ok())
        now += 6_000; rules.tick()
        now += 21_000; rules.tick()
        rules.tick()
        assertEquals("0", flag("node", "node_08", "lockdown_until"))
        assertEquals("denied", (data("node_cfg", "node_08")["goal"] as JsonObject).str("result"))
    }

    @Test fun templateAppliesInOneOperation() {
        val m = Client("master")
        val put = m.req(
            "put",
            """"type":"template","id":"tpl_night","ver":0,"data":{"title":"Ночь","settings":{"soft_ice_reentry_pause_s":60,"world_pub":"EVIL","await_flatline":1},"node_cfg":{"trace_per_s":4}}""",
        )
        assertTrue(put.toString(), put.ok())
        val r = m.req("master.template_apply", """"template":"tpl_night","nodes":["node_07","node_08"]""")
        assertTrue(r.toString(), r.ok())
        assertEquals("60", flag("settings", "global", "soft_ice_reentry_pause_s"))
        assertEquals("1", flag("settings", "global", "await_flatline"))
        assertEquals("WP", flag("settings", "global", "world_pub")) // ключ мира шаблоном не меняется
        assertEquals("4", flag("node_cfg", "node_07", "trace_per_s"))
        assertEquals("4", flag("node_cfg", "node_08", "trace_per_s"))
        assertEquals("tpl_night", (data("settings", "global")["template_applied"] as JsonObject).str("id"))

        // нет узла — ничего не записано
        store.put("template", "tpl_b", 0, JsonObject(mapOf("settings" to JsonObject(mapOf("zzz" to JsonPrimitive(1))), "node_cfg" to JsonObject(mapOf("a" to JsonPrimitive(1))))))
        assertEquals("not_found", m.req("master.template_apply", """"template":"tpl_b","nodes":["node_07","node_99"]""").code())
        assertFalse(data("settings", "global").containsKey("zzz"))
        assertEquals("bad_request", m.req("master.template_apply", """"template":"tpl_b"""").code())
        assertEquals("not_found", m.req("master.template_apply", """"template":"nope"""").code())
    }

    @Test fun queryChannelBetweenRunnerAndMaster() {
        val w = Client("world")
        val m = Client("master")
        val q = w.req("net.query", """"runner":"Призрак","mid":"m1","text":"Где шард?"""")
        assertTrue(q.toString(), q.ok())
        val id = q["doc"]!!.jsonObject.str("id")
        assertEquals("open", flag("net_query", id, "state"))
        assertEquals(1, store.list("alert").count { it.data["kind"]!!.jsonPrimitive.content == "net_query" })
        // повтор того же mid не дублирует
        assertTrue(w.req("net.query", """"query":"$id","runner":"Призрак","mid":"m1","text":"Где шард?"""").ok())
        assertEquals(1, (data("net_query", id)["messages"] as kotlinx.serialization.json.JsonArray).size)

        val rep = m.req("master.reply", """"query":"$id","mid":"r1","text":"В узле 7"""")
        assertTrue(rep.toString(), rep.ok())
        assertEquals("answered", flag("net_query", id, "state"))
        assertEquals("not_found", m.req("master.reply", """"query":"zz","mid":"r2","text":"x"""").code())
        // нетраннер пишет ещё раз: запрос снова open, сообщений три
        assertTrue(w.req("net.query", """"query":"$id","runner":"Призрак","mid":"m2","text":"Спасибо"""").ok())
        assertEquals("open", flag("net_query", id, "state"))
        val msgs = data("net_query", id)["messages"]!!.jsonArray
        assertEquals(listOf("runner", "master", "runner"), msgs.map { it.jsonObject.str("from") })
        assertEquals("bad_request", w.req("net.query", """"runner":"Призрак","mid":"m3","text":""""").code())
    }
}
