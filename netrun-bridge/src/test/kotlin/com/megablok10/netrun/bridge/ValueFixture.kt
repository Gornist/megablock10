package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.io.File
import java.util.Collections

/** Стенд для тестов операций с ценностями и аудитора: узел с запасом эдди, два терминала, два игрока, добыча в узле. */
class ValueFixture(val path: String) {
    var calls = 0
    var failAt = -1
    private var now = 1_000L
    val clock: () -> Long = {
        calls++
        if (calls == failAt) error("сбой на вызове часов $calls")
        now++
    }
    /** Текущее время стенда без шага часов: «сейчас» для того, кто сверяет сроки событий с временем документов. */
    val nowMs: Long get() = now

    /** Перевести часы стенда вперёд на [ms] (длительности забегов в тестах считаются секундами). */
    fun advance(ms: Long) { now += ms }

    val store: DocStore = DocStore.open(path, clock)
    val issued: MutableList<IssuedTransfer> = Collections.synchronizedList(ArrayList())
    val ops = ValueOps(store, clock) { issued.addAll(it) }

    val world = Caller(Role.WORLD, "world-main")
    val master = Caller(Role.MASTER, "master-anna")
    val test = Caller(Role.TEST, "test")

    val keyA = "KEY_A"
    val keyB = "KEY_B"
    private val allTypes = setOf(
        "item", "deck", "session", "node", "runner", "alert", "payout", "op_rid", "terminal", "settings",
    )

    fun obj(vararg p: Pair<String, Any?>) = JsonObject(
        p.associate { (k, v) ->
            k to when (v) {
                null -> kotlinx.serialization.json.JsonNull
                is Long -> JsonPrimitive(v)
                is Int -> JsonPrimitive(v.toLong())
                is Boolean -> JsonPrimitive(v)
                is String -> JsonPrimitive(v)
                else -> error("тип $v")
            }
        },
    )

    fun item(id: String, owner: String, origin: String, protectedFlag: Boolean = false, kind: String = "DAEMON") {
        store.put(
            "item", id, 0,
            obj(
                "owner" to owner, "kind" to kind, "payload" to "p-$id", "protected" to protectedFlag, "origin" to origin,
                "in_transfer" to null, "out_transfer" to null, "handover" to null,
            ),
        )
    }

    init {
        store.put("node", "node_07", 0, obj("tier" to "STANDARD", "lockdown_until" to 0L, "eddies" to 300L))
        store.put("terminal", "t03", 0, obj("node" to "node_07", "label" to "стойка 3"))
        store.put("terminal", "t04", 0, obj("node" to "node_07", "label" to "стойка 4"))
        for (k in listOf(keyA, keyB)) {
            store.put(
                "runner", ValueOps.runnerDocId(k), 0,
                obj("key" to k, "callsign" to k, "blocked" to false, "runs" to 1, "tutorial_done" to true),
            )
        }
        item("it_dA1", "inbox:$keyA", "phone:$keyA")
        item("it_dA2", "inbox:$keyA", "phone:$keyA")
        item("it_dB1", "inbox:$keyB", "phone:$keyB")
        item("it_dB2", "inbox:$keyB", "phone:$keyB")
        item("it_sh1", "node:node_07", "node:node_07", kind = "SHARD")
        item("it_sh2", "node:node_07", "node:node_07", kind = "SHARD")
        calls = 0
    }

    val itemCount = 6
    val eddiesTotal = 300L

    fun sessionOf(r: OpResult): String = VJ.str(r.body, "session")!!

    /** Сдать деку игрока [key] и сразу «нажать курок» (confirm делает сервер мира, здесь — прямой put). */
    fun enterActive(key: String, terminal: String, vararg items: String): String {
        val r = ops.submitDeck(test, "enter:e-$key", key, key, terminal, items.toList(), items.first())
        assertTrue(r.body.toString(), r.ok)
        val sid = sessionOf(r)
        activate(sid)
        return sid
    }

    fun activate(sid: String) {
        val s = store.get("session", sid)!!
        store.put("session", sid, s.ver, VJ.with(s.data, "state" to JsonPrimitive("active")))
    }

    fun snapshot(): Pair<Long, List<Doc>> = store.snapshot(allTypes)

    fun owner(item: String): String = VJ.str(store.get("item", item)!!.data, "owner")!!

    /** Инварианты: предметов столько же, у каждого один владелец, аудитор чист, эдди сохранились. */
    fun assertConserved() {
        assertEquals(itemCount, store.list("item").size)
        assertEquals(emptyList<Violation>(), Auditor(store).check())
        val node = store.list("node").sumOf { VJ.lng(it.data, "eddies") }
        val loot = store.list("session").sumOf { VJ.lng(it.data, "loot_eddies") }
        val pay = store.list("payout").sumOf { VJ.lng(it.data, "eddies") }
        assertEquals(eddiesTotal, node + loot + pay)
    }

    companion object {
        fun newPath(dir: File, name: String): String = dir.resolve(name).path
    }
}
