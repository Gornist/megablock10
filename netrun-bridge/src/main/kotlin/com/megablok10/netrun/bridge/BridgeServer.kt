package com.megablok10.netrun.bridge

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.java_websocket.WebSocket
import org.java_websocket.framing.Framedata
import org.java_websocket.handshake.ClientHandshake
import org.java_websocket.server.WebSocketServer
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * API Моста по WebSocket `/netrun/v1` (docs/netrun-bridge-protocol.md): `hello` с ролью, `get`/`list`, `put`/`del` с версией,
 * `sub`/`unsub` с потоком `chg`. Операции с ценностями (раздел 6) идут через [ValueOps], терминал и сессия (раздел 7) — через
 * [TerminalOps]; роль из `hello` становится [Caller] операции.
 */
class BridgeServer(
    private val store: DocStore,
    private val config: BridgeConfig,
    private val ops: ValueOps = ValueOps(store),
    private val terminals: TerminalOps = TerminalOps(store),
) {
    private class Conn {
        @Volatile var role: String? = null
        @Volatile var client: String? = null
        @Volatile var lastActivity = System.currentTimeMillis()
        val subs: MutableSet<String> = ConcurrentHashMap.newKeySet()
    }

    private val router = OpRouter(ops, terminals)
    private val conns = ConcurrentHashMap<WebSocket, Conn>()
    private val started = CountDownLatch(1)
    private var startError: Exception? = null
    private val watchdog: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "netrun-bridge-watchdog").apply { isDaemon = true }
    }

    private val ws = object : WebSocketServer(InetSocketAddress(config.port)) {
        override fun onOpen(conn: WebSocket, handshake: ClientHandshake) {
            if (handshake.resourceDescriptor.substringBefore('?') != PATH) {
                conn.close(1008, "путь $PATH")
                return
            }
            conns[conn] = Conn()
        }

        override fun onClose(conn: WebSocket, code: Int, reason: String?, remote: Boolean) {
            conns.remove(conn)
        }

        override fun onMessage(conn: WebSocket, message: String) {
            conns[conn]?.let { handleText(conn, it, message) }
        }

        override fun onMessage(conn: WebSocket, message: ByteBuffer) {
            conns[conn] ?: return
            conn.send(errReply(null, StoreException("bad_request", "бинарные кадры не поддерживаются")).toString())
            conn.close(1003, "binary")
        }

        override fun onWebsocketPing(conn: WebSocket, f: Framedata) {
            conns[conn]?.lastActivity = System.currentTimeMillis()
            super.onWebsocketPing(conn, f)
        }

        override fun onError(conn: WebSocket?, ex: Exception) {
            if (conn == null) startError = ex // сбой старта (порт занят); остальное — обрыв клиента, обычное дело
        }

        override fun onStart() {
            started.countDown()
        }
    }

    /** Порт, на котором слушает сервер (после [start] — настоящий, даже если в конфиге 0). */
    val port: Int get() = ws.port

    /** Запускает сервер и ждёт, пока порт открыт; занятый порт — исключение. */
    fun start() {
        ws.isReuseAddr = true
        ws.connectionLostTimeout = 0 // тишину считаем сами (30 с по протоколу), встроенные пинги отключены
        store.addListener(::broadcast)
        ws.start()
        started.await()
        startError?.let { throw it }
        val period = (config.idleTimeoutMs / 4).coerceIn(50, 5_000)
        watchdog.scheduleWithFixedDelay(::closeIdle, period, period, TimeUnit.MILLISECONDS)
    }

    fun stop() {
        watchdog.shutdownNow()
        ws.stop(1000)
    }

    private fun closeIdle() {
        val limit = System.currentTimeMillis() - config.idleTimeoutMs
        conns.forEach { (c, s) -> if (s.lastActivity < limit) c.close(1001, "idle") }
    }

    /** Слушатель хранилища: зовётся под замком хранилища в порядке `seq`, поэтому порядок пушей у всех подписчиков тот же. */
    private fun broadcast(changes: List<Change>) {
        conns.forEach { (c, s) ->
            if (s.subs.isEmpty()) return@forEach
            val mine = changes.filter { it.doc.type in s.subs }
            mine.forEachIndexed { i, ch -> safeSend(c, ch.toPush(i == mine.lastIndex)) }
        }
    }

    private fun safeSend(c: WebSocket, msg: JsonObject) {
        try {
            c.send(msg.toString())
        } catch (_: org.java_websocket.exceptions.WebsocketNotConnectedException) {
            // соединение уже закрылось — подписчик снимется в onClose
        }
    }

    private fun handleText(conn: WebSocket, s: Conn, text: String) {
        s.lastActivity = System.currentTimeMillis()
        val msg = try {
            Json.parseToJsonElement(text) as? JsonObject
        } catch (_: SerializationException) {
            null
        }
        val cid = msg?.get("cid").string()
        if (msg == null || cid == null || !validCid(cid)) {
            safeSend(conn, errReply(cid?.takeIf(::validCid), StoreException("bad_request", "нужен JSON-объект с cid (≤ $MAX_CID)")))
            return
        }
        var close = false
        val reply = try {
            okReply(cid, dispatch(s, msg))
        } catch (e: StoreException) {
            close = e.code == "unsupported_version" || (msg["op"].string() == "hello" && e.code == "unauthorized")
            errReply(cid, e)
        }
        safeSend(conn, reply)
        if (close) conn.close(1008, "rejected")
    }

    private fun dispatch(s: Conn, msg: JsonObject): Map<String, JsonElement> {
        if (msg["v"].long() != NETRUN_PROTO.toLong()) throw StoreException("unsupported_version", "поддержан v=$NETRUN_PROTO")
        val op = msg["op"].string() ?: throw StoreException("bad_request", "нет op")
        if (op == "hello") return hello(s, msg)
        val role = s.role ?: throw StoreException("unauthorized", "сначала hello")
        return when (op) {
            "get" -> get(msg)
            "list" -> list(msg)
            "put" -> put(role, msg)
            "del" -> del(role, msg)
            "sub" -> sub(s, msg)
            "unsub" -> unsub(s, msg)
            else -> router.handle(Caller(callerRole(role), s.client ?: ""), op, msg)
        }
    }

    private fun callerRole(role: String) = when (role) {
        "world" -> Role.WORLD
        "master" -> Role.MASTER
        else -> Role.TEST
    }

    private fun hello(s: Conn, msg: JsonObject): Map<String, JsonElement> {
        if (s.role != null) throw StoreException("bad_request", "hello уже был")
        if (msg["proto"].long() != NETRUN_PROTO.toLong()) throw StoreException("unsupported_version", "поддержан proto=$NETRUN_PROTO")
        val role = msg["role"].string()
        val client = msg["client"].string()?.takeIf { it.isNotEmpty() && it.length <= MAX_CID }
            ?: throw StoreException("bad_request", "нужен client")
        val key = msg["key"].string()
        val expected = config.roleKeys[role]
        val roleOk = role in ROLES && (role != "test" || config.testMode)
        val keyOk = expected != null && key != null &&
            MessageDigest.isEqual(expected.toByteArray(), key.toByteArray())
        if (!roleOk || !keyOk) throw StoreException("unauthorized", "неверная роль или ключ")
        s.client = client
        s.role = role
        return buildMap {
            put("proto", JsonPrimitive(NETRUN_PROTO))
            put("bridge", JsonPrimitive(config.bridgeVersion))
            put("now", JsonPrimitive(System.currentTimeMillis()))
            config.worldPub?.let { put("world_pub", JsonPrimitive(it)) }
        }
    }

    private fun validCid(cid: String) = cid.isNotEmpty() && cid.length <= MAX_CID

    private fun key(msg: JsonObject): Pair<String, String> {
        val type = msg["type"].string()?.takeIf(::isValidType)
        val id = msg["id"].string()?.takeIf(::isValidId)
        return (type ?: throw StoreException("bad_request", "нужен type")) to (id ?: throw StoreException("bad_request", "нужен id"))
    }

    private fun typeOf(msg: JsonObject): String =
        msg["type"].string()?.takeIf(::isValidType) ?: throw StoreException("bad_request", "нужен type")

    private fun get(msg: JsonObject): Map<String, JsonElement> {
        val (type, id) = key(msg)
        val doc = store.get(type, id) ?: throw StoreException("not_found", "документа нет")
        return mapOf("doc" to doc.toJson())
    }

    private fun list(msg: JsonObject): Map<String, JsonElement> {
        val (seq, docs) = store.snapshot(setOf(typeOf(msg)))
        return mapOf("seq" to JsonPrimitive(seq), "docs" to JsonArray(docs.map { it.toJson() }))
    }

    private fun put(role: String, msg: JsonObject): Map<String, JsonElement> {
        val (type, id) = key(msg)
        val ver = msg["ver"].long()?.takeIf { it >= 0 } ?: throw StoreException("bad_request", "нужен ver ≥ 0")
        val data = msg["data"] as? JsonObject ?: throw StoreException("bad_request", "data — объект")
        WriteGuard.checkRole(role, type)
        // Проверка ценностей и запись — одна транзакция, иначе между ними может вклиниться чужая запись.
        val doc = store.transaction { tx ->
            WriteGuard.checkValues(type, tx.get(type, id), data)
            tx.put(type, id, ver, data)
        }
        return mapOf("doc" to doc.toJson())
    }

    private fun del(role: String, msg: JsonObject): Map<String, JsonElement> {
        val (type, id) = key(msg)
        val ver = msg["ver"].long()?.takeIf { it >= 1 } ?: throw StoreException("bad_request", "нужен ver ≥ 1")
        WriteGuard.checkRole(role, type)
        store.transaction { tx ->
            WriteGuard.checkValues(type, tx.get(type, id), null)
            tx.delete(type, id, ver)
        }
        return emptyMap()
    }

    private fun types(msg: JsonObject): Set<String> {
        val arr = msg["types"] as? JsonArray ?: throw StoreException("bad_request", "types — массив")
        val set = arr.map { it.string()?.takeIf(::isValidType) ?: throw StoreException("bad_request", "неверный тип в types") }.toSet()
        if (set.isEmpty()) throw StoreException("bad_request", "types пуст")
        return set
    }

    /**
     * Снимок и включение подписки — под замком хранилища: запись, прошедшая после снимка, дойдёт пушем уже после ответа
     * (слушатель хранилища тоже под этим замком), а прошедшая до — попадёт в снимок. Пропусков и дублей нет.
     */
    private fun sub(s: Conn, msg: JsonObject): Map<String, JsonElement> {
        val want = types(msg)
        synchronized(store) {
            val fresh = want - s.subs
            val (seq, docs) = store.snapshot(fresh)
            s.subs.addAll(fresh)
            return mapOf("seq" to JsonPrimitive(seq), "docs" to JsonArray(docs.map { it.toJson() }))
        }
    }

    private fun unsub(s: Conn, msg: JsonObject): Map<String, JsonElement> {
        s.subs.removeAll(types(msg))
        return emptyMap()
    }

    companion object {
        const val PATH = "/netrun/v1"
        private const val MAX_CID = 64
        private val ROLES = setOf("world", "master", "test")
    }
}
