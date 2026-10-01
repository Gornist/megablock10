package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.TimeUnit

/** Полный забег через фейковый сервер мира по настоящему WebSocket: вход, сессия, шард, выход, повтор. */
class FakeWorldRunTest {
    @get:Rule val tmp = TemporaryFolder()

    private lateinit var store: DocStore
    private lateinit var server: BridgeServer
    private lateinit var world: FakeWorldServer

    private val runnerKey = "KEY_RUNNER"
    private val token = "token-of-t03"

    @Before fun setUp() {
        store = DocStore.open(tmp.root.resolve("b.db").path)
        ensureDefaultSettings(store)
        server = BridgeServer(store, BridgeConfig(port = 0, roleKeys = mapOf("world" to "kw", "master" to "km", "test" to "kt"), testMode = true))
        server.start()
        world = FakeWorldServer(server.port, "kt")
        seed()
    }

    @After fun tearDown() {
        world.close()
        server.stop()
        store.close()
    }

    private fun seed() {
        store.put("node", "node_07", 0, VJ.obj("tier" to VJ.p("STANDARD"), "lockdown_until" to VJ.p(0L), "eddies" to VJ.p(0L)))
        store.put("terminal", "t03", 0, VJ.obj("node" to VJ.p("node_07"), "label" to VJ.p("стойка 3"), "token_sha256" to VJ.p(VJ.sha256Hex(token))))
        // Игрок уже проходил обучение, иначе Мост отправит его в учебный узел.
        store.put(
            "runner", ValueOps.runnerDocId(runnerKey), 0,
            VJ.obj("key" to VJ.p(runnerKey), "callsign" to VJ.p("Призрак"), "blocked" to VJ.p(false), "runs" to VJ.p(1L), "tutorial_done" to VJ.p(true)),
        )
        item("it_d1", "inbox:$runnerKey", "DAEMON", "phone:$runnerKey", true)
        item("it_d2", "inbox:$runnerKey", "DAEMON", "phone:$runnerKey", false)
        item("it_sh1", "node:node_07", "SHARD", "node:node_07", false)
    }

    private fun item(id: String, owner: String, kind: String, origin: String, prot: Boolean) {
        store.put(
            "item", id, 0,
            VJ.obj(
                "owner" to VJ.p(owner), "kind" to VJ.p(kind), "payload" to VJ.p("p-$id"), "protected" to VJ.p(prot),
                "origin" to VJ.p(origin), "in_transfer" to kotlinx.serialization.json.JsonNull,
                "out_transfer" to kotlinx.serialization.json.JsonNull, "handover" to kotlinx.serialization.json.JsonNull,
            ),
        )
    }

    private fun JsonObject.str(vararg path: String): String {
        var cur: JsonObject = this
        for (p in path.dropLast(1)) cur = cur[p]!!.jsonObject
        return cur[path.last()]!!.jsonPrimitive.content
    }

    private fun owner(id: String) = VJ.str(store.get("item", id)!!.data, "owner")

    @Test fun fullRunThroughFakeWorld() {
        assertTrue(world.ok(world.hello()))
        val snap = world.req("sub", """"types":["session","item"]""")
        assertTrue(world.ok(snap))

        // Токен терминала: плохой не пускает, настоящий — да, открытой сессии ещё нет.
        assertEquals("bad_token", world.code(world.req("terminal.auth", """"terminal":"t03","token":"чужой"""")))
        val auth = world.req("terminal.auth", """"terminal":"t03","token":"$token"""")
        assertTrue(world.ok(auth))
        assertEquals("null", auth["session"]!!.toString())

        // Дека сдана (это делает приём карточек, у фейка — роль test) -> сессия pending, предметы в деке.
        val deck = world.req(
            "op.submit_deck",
            """"rid":"enter:e-1","runner":"$runnerKey","callsign":"Призрак","terminal":"t03","items":["it_d1","it_d2"],"protected":"it_d1"""",
        )
        assertTrue(deck.toString(), world.ok(deck))
        val sid = deck.str("session")
        assertEquals("pending", deck.str("state"))
        assertEquals("deck:$sid", owner("it_d1"))
        assertEquals(sid, world.req("terminal.auth", """"terminal":"t03","token":"$token"""")["session"]!!.jsonObject.str("id"))

        // Курок, затем шард из узла.
        assertEquals("active", world.req("session.confirm", """"session":"$sid","terminal":"t03"""").str("session", "data", "state"))
        val takeRid = "take:$sid:it_sh1"
        val take = world.req("op.take_from_node", """"rid":"$takeRid","session":"$sid","node":"node_07","item":"it_sh1"""")
        assertTrue(take.toString(), world.ok(take))
        assertEquals("deck:$sid", owner("it_sh1"))

        // Повтор взятия с тем же rid не берёт второй раз.
        val again = world.req("op.take_from_node", """"rid":"$takeRid","session":"$sid","node":"node_07","item":"it_sh1"""")
        assertEquals("true", again["replayed"]!!.jsonPrimitive.content)

        // Выход чистый: всё на телефон. Защищённого демона Мост добавляет сам, его в moves нет.
        val finishBody = """"rid":"finish:$sid","session":"$sid","outcome":"clean","node":"node_07","disconnect":false,""" +
            """"moves":[{"item":"it_d2","to":"phone"},{"item":"it_sh1","to":"phone"}]"""
        val fin = world.req("run.finish", finishBody)
        assertTrue(fin.toString(), world.ok(fin))
        assertEquals("closed", fin.str("session", "data", "state"))
        assertEquals("clean", fin.str("session", "data", "outcome"))
        assertEquals(3, fin["transfers"]!!.jsonArray.size)
        for (id in listOf("it_d1", "it_d2", "it_sh1")) assertEquals("outbox:$runnerKey", owner(id))

        // Рестарт сервера мира посреди выхода: тот же детерминированный rid -> тот же ответ.
        val replay = world.req("run.finish", finishBody)
        assertEquals("true", replay["replayed"]!!.jsonPrimitive.content)
        assertEquals(3, replay["transfers"]!!.jsonArray.size)
        assertEquals(emptyList<Violation>(), Auditor(store).check())

        // Пуши пришли: подписка на session/item видела изменения.
        val seen = ArrayList<String>()
        while (true) seen.add((world.pushes.poll(300, TimeUnit.MILLISECONDS) ?: break)["doc"]!!.jsonObject.str("type"))
        assertTrue(seen.toString(), "session" in seen && "item" in seen)
    }
}
