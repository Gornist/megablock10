package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull
import java.security.MessageDigest

/** Мелкие помощники разбора и сборки JSON для операций с ценностями и аудитора (внутри модуля). */
internal object VJ {
    fun str(o: JsonObject, k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    fun lng(o: JsonObject, k: String): Long = (o[k] as? JsonPrimitive)?.longOrNull ?: 0L
    fun bool(o: JsonObject, k: String): Boolean = (o[k] as? JsonPrimitive)?.booleanOrNull ?: false
    fun list(o: JsonObject, k: String): List<String> =
        (o[k] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: emptyList()

    fun with(o: JsonObject, vararg p: Pair<String, JsonElement>): JsonObject = JsonObject(o + p)
    fun obj(vararg p: Pair<String, JsonElement>): JsonObject = JsonObject(mapOf(*p))
    fun arr(l: List<String>): JsonArray = JsonArray(l.map { JsonPrimitive(it) })
    fun p(s: String?): JsonElement = if (s == null) JsonNull else JsonPrimitive(s)
    fun p(n: Long): JsonElement = JsonPrimitive(n)
    fun p(b: Boolean): JsonElement = JsonPrimitive(b)

    fun docJson(d: Doc): JsonObject = obj(
        "type" to p(d.type), "id" to p(d.id), "ver" to p(d.ver),
        "created" to p(d.created), "updated" to p(d.updated), "data" to d.data,
    )

    fun sha256Hex(s: String): String =
        MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
}
