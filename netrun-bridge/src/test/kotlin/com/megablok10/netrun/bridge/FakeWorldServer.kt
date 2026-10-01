package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.net.http.HttpClient
import java.net.http.WebSocket
import java.util.concurrent.CompletionStage
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Фейковый сервер мира (F1): клиент WebSocket, который говорит с Мостом по протоколу (docs/netrun-bridge-protocol.md) ролью
 * `test`: сдаёт деку, подтверждает сессию, берёт шард, завершает забег. Настоящего Godot не нужно — им проверяют Мост.
 * Запросы синхронные, ответ ищется по `cid`; пуши `chg` копятся в [pushes].
 */
class FakeWorldServer(port: Int, private val key: String, private val client: String = "fake-world") : AutoCloseable {
    val pushes = LinkedBlockingQueue<JsonObject>()
    private val replies = LinkedBlockingQueue<JsonObject>()
    private val buf = StringBuilder()
    private var n = 0
    private val ws: WebSocket = HttpClient.newHttpClient().newWebSocketBuilder()
        .buildAsync(
            URI("ws://127.0.0.1:$port${BridgeServer.PATH}"),
            object : WebSocket.Listener {
                override fun onText(w: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                    buf.append(data)
                    if (last) {
                        val m = Json.parseToJsonElement(buf.toString()).jsonObject
                        buf.clear()
                        if (m.containsKey("push")) pushes.add(m) else replies.add(m)
                    }
                    w.request(1)
                    return null
                }
            },
        ).get(TIMEOUT_S, TimeUnit.SECONDS)

    /** Один запрос — один ответ с тем же `cid` (протокол, раздел 2). [body] — поля без скобок и без `op`. */
    fun req(op: String, body: String = ""): JsonObject {
        val cid = "fw-${++n}"
        ws.sendText("""{"v":1,"cid":"$cid","op":"$op"${if (body.isEmpty()) "" else ",$body"}}""", true).get(TIMEOUT_S, TimeUnit.SECONDS)
        val r = replies.poll(TIMEOUT_S, TimeUnit.SECONDS) ?: error("нет ответа на $op за $TIMEOUT_S с")
        check(r["re"]?.jsonPrimitive?.content == cid) { "ответ не на $cid: $r" }
        return r
    }

    fun hello(): JsonObject = req("hello", """"proto":$NETRUN_PROTO,"role":"test","client":"$client","key":"$key"""")

    fun ok(r: JsonObject): Boolean = r["ok"]?.jsonPrimitive?.content == "true"

    fun code(r: JsonObject): String = r["err"]!!.jsonObject["code"]!!.jsonPrimitive.content

    override fun close() { runCatching { ws.abort() } }

    private companion object {
        const val TIMEOUT_S = 5L
    }
}
