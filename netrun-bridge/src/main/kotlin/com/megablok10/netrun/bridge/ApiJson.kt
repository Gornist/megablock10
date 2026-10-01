package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** Документ в JSON протокола (раздел 4). */
fun Doc.toJson(): JsonObject = buildJsonObject {
    put("type", type); put("id", id); put("ver", ver); put("created", created); put("updated", updated)
    put("data", data)
}

/** Кадр `chg` потока изменений (раздел 4); [last] пересчитан по тому, что реально уходит подписчику. */
fun Change.toPush(last: Boolean): JsonObject = buildJsonObject {
    put("v", NETRUN_PROTO); put("push", "chg"); put("seq", seq); put("last", last)
    if (deleted) put("deleted", true)
    put("doc", doc.toJson())
}

internal fun okReply(cid: String, extra: Map<String, JsonElement> = emptyMap()): JsonObject = buildJsonObject {
    put("v", NETRUN_PROTO); put("re", cid); put("ok", true)
    extra.forEach { (k, v) -> put(k, v) }
}

internal fun errReply(cid: String?, e: StoreException): JsonObject = buildJsonObject {
    put("v", NETRUN_PROTO)
    if (cid != null) put("re", cid)
    put("ok", false)
    put(
        "err",
        buildJsonObject {
            put("code", e.code); put("msg", e.message ?: e.code)
            e.current?.let { put("doc", it.toJson()) }
        },
    )
}

internal fun JsonElement?.string(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
internal fun JsonElement?.long(): Long? = (this as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
