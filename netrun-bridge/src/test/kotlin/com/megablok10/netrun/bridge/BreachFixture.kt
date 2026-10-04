package com.megablok10.netrun.bridge

import com.megablok10.rules.Daemon
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.ShardPayload
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertTrue
import java.util.Collections
import kotlin.random.Random

/**
 * Стенд для `run.breach`: узел `node_07` (тир HARD, запас 300 эдди, фракция «Арасака», хранилища-шарды тиров 1..3 и демон), учебный
 * `node_00`, два нетраннера фракции «Корпа» с настоящими демонами в картах (разбор `daemon` — как при приёме карточки) и
 * активными сессиями. Часы стенда идут на 1 мс за вызов и умеют падать на заданном вызове.
 */
class BreachFixture(path: String = ":memory:") {
    var calls = 0
    var failAt = -1
    private var now = 10_000_000L
    val clock: () -> Long = {
        calls++
        if (calls == failAt) error("сбой на вызове часов $calls")
        now++
    }
    val nowMs: Long get() = now
    fun advance(ms: Long) { now += ms }

    val store: DocStore = DocStore.open(path, clock)
    val issued: MutableList<IssuedTransfer> = Collections.synchronizedList(ArrayList())
    val ops = ValueOps(store, clock) { issued.addAll(it) }
    val world = Caller(Role.WORLD, "world-main")
    val keyA = "KEY_A"
    val keyB = "KEY_B"

    private fun str(vararg p: Pair<String, Any?>) = JsonObject(
        p.associate { (k, v) ->
            k to when (v) {
                null -> JsonNull
                is Long -> JsonPrimitive(v)
                is Int -> JsonPrimitive(v.toLong())
                is Boolean -> JsonPrimitive(v)
                else -> JsonPrimitive(v.toString())
            }
        },
    )

    /** Предмет-демон в `inbox` игрока [key]: цепочка из двух кодов, [effect], [tier]. */
    private fun daemonItem(id: String, key: String, effect: DaemonEffect, tier: Tier) {
        val d = Daemon(id, id, listOf("1C", "55"), tier, effect)
        val payload = ItemPayloadCodec.encodeDaemon(d)
        put(id, "inbox:$key", "phone:$key", "DAEMON", payload)
    }

    /** Предмет узла (хранилище): шард или демон заданного тира, [origin] — `node:node_07` либо `master:...`. */
    fun vaultItem(id: String, kind: String, tier: Tier, origin: String = "node:node_07", owner: String = "node:node_07") {
        val payload = if (kind == "SHARD") {
            ItemPayloadCodec.encodeShard(ShardPayload(id, true, tier.level, "", "Шард $id", "", "тело", 0, false))
        } else {
            ItemPayloadCodec.encodeDaemon(Daemon(id, id, listOf("BD", "E9"), tier, DaemonEffect.EXTRACT_SHARD))
        }
        put(id, owner, origin, kind, payload)
    }

    private fun put(id: String, owner: String, origin: String, kind: String, payload: String) {
        val fields = ItemDecode.fields(kind, payload)
        store.put(
            "item", id, 0,
            JsonObject(
                str(
                    "owner" to owner, "kind" to kind, "payload" to payload, "protected" to false, "origin" to origin,
                    "in_transfer" to null, "out_transfer" to null, "handover" to null,
                ) + fields,
            ),
        )
    }

    /** Демоны игрока A (по два кода): добыча, майнер, три глушителя сигнала и два экстрактора. */
    val daemonsA = listOf(
        "it_ex" to DaemonEffect.EXTRACT_SHARD, "it_exd" to DaemonEffect.EXTRACT_DAEMON, "it_miner" to DaemonEffect.MINER,
        "it_ghost" to DaemonEffect.GHOST, "it_time" to DaemonEffect.TIMESKEW, "it_black" to DaemonEffect.BLACKOUT,
    )

    init {
        store.put("settings", "global", 0, str("tutorial_node" to "node_00", "node_lockdown_s" to 600L))
        store.put("settings", "sec", 0, JsonObject(mapOf("factions" to JsonObject(mapOf("Арасака" to JsonArray(listOf(JsonPrimitive("sec1"), JsonPrimitive("sec2"))))))))
        store.put("node", "node_00", 0, str("tier" to "BASE", "tutorial" to true, "lockdown_until" to 0L, "eddies" to 0L))
        store.put("node", "node_07", 0, str("tier" to "HARD", "title" to "Склад Арасаки", "owner_faction" to "Арасака", "lockdown_until" to 0L, "eddies" to 300L))
        store.put("terminal", "t03", 0, str("node" to "node_07", "label" to "стойка 3"))
        store.put("terminal", "t04", 0, str("node" to "node_07", "label" to "стойка 4"))
        for (k in listOf(keyA, keyB)) {
            store.put(
                "runner", ValueOps.runnerDocId(k), 0,
                str("key" to k, "callsign" to k, "blocked" to false, "runs" to 1, "tutorial_done" to true, "faction" to "Корпа"),
            )
        }
        for ((id, effect) in daemonsA) daemonItem(id, keyA, effect, Tier.HARD)
        daemonItem("it_b1", keyB, DaemonEffect.EXTRACT_SHARD, Tier.NIGHTMARE)
        daemonItem("it_b2", keyB, DaemonEffect.MINER, Tier.BASE)
        vaultItem("v_sh1", "SHARD", Tier.BASE)
        vaultItem("v_sh2", "SHARD", Tier.HARD)
        vaultItem("v_sh3", "SHARD", Tier.NIGHTMARE)
        vaultItem("v_dm1", "DAEMON", Tier.BASE)
        calls = 0
    }

    /** Сдать деку игрока и «нажать курок». Возвращает id сессии. */
    fun enter(key: String, terminal: String, vararg items: String): String {
        val r = ops.submitDeck(Caller(Role.TEST, "test"), "enter:e-$key", key, key, terminal, items.toList(), items.first())
        assertTrue(r.body.toString(), r.ok)
        val sid = VJ.str(r.body, "session")!!
        activate(sid)
        return sid
    }

    fun enterA(): String = enter(keyA, "t03", *daemonsA.map { it.first }.toTypedArray())
    fun enterB(): String = enter(keyB, "t04", "it_b1", "it_b2")

    fun activate(sid: String) {
        val s = store.get("session", sid)!!
        store.put("session", sid, s.ver, VJ.with(s.data, "state" to JsonPrimitive("active")))
    }

    fun setWorld(sid: String, vararg p: Pair<String, JsonPrimitive>) {
        val s = store.get("session", sid)!!
        val w = s.data["world"] as JsonObject
        store.put("session", sid, s.ver, VJ.with(s.data, "world" to JsonObject(w + p)))
    }

    fun req(
        sid: String,
        n: Long = 1,
        tier: String = "HARD",
        selected: List<String>,
        matched: List<String> = selected,
        active: List<String> = emptyList(),
        vaults: List<String> = listOf("v_sh1", "v_sh2", "v_sh3", "v_dm1"),
        openS: Long = 60,
        node: String = "node_07",
    ) = BreachRequest(sid, node, n, tier, selected, matched, active, vaults, openS)

    fun breach(sid: String, q: BreachRequest, rid: String = "breach:$sid:${q.n}", caller: Caller = world): OpResult =
        ops.runBreach(caller, rid, q)

    fun session(sid: String): JsonObject = store.get("session", sid)!!.data
    fun runner(key: String): JsonObject = store.get("runner", ValueOps.runnerDocId(key))!!.data
    fun nodeEddies(): Long = VJ.lng(store.get("node", "node_07")!!.data, "eddies")
    fun owner(item: String): String = VJ.str(store.get("item", item)!!.data, "owner")!!
    fun secAlerts(): List<Doc> = store.list("sec_alert")

    /** Ожидаемые эдди: тот же бросок, что у Моста, зерно — `<namespace>|<rid>`. */
    fun expectedRoll(rid: String, tier: Tier): Long {
        val seed = java.lang.Long.parseUnsignedLong(VJ.sha256Hex("world/world-main|$rid").take(16), 16)
        return com.megablok10.rules.ContainerEddies.roll(tier, Random(seed))
    }

    /** Всего эдди в мире: запас узлов + добыча сессий + выплаты. */
    fun eddiesTotal(): Long =
        store.list("node").sumOf { VJ.lng(it.data, "eddies") } + store.list("session").sumOf { VJ.lng(it.data, "loot_eddies") } +
            store.list("payout").sumOf { VJ.lng(it.data, "eddies") }
}
