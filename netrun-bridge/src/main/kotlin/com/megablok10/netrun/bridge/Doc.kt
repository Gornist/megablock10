package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject

/** Документ Моста (протокол, раздел 4): пара [type]+[id] уникальна, [ver] растёт на каждое изменение. */
data class Doc(
    val type: String,
    val id: String,
    val ver: Long,
    val created: Long,
    val updated: Long,
    val data: JsonObject,
)

/** Изменение документа в потоке (`chg`): [deleted] — документ удалён, [doc] — его последняя версия. */
data class Change(val seq: Long, val last: Boolean, val doc: Doc, val deleted: Boolean = false)

/** Ключ документа. */
data class DocKey(val type: String, val id: String)

private val TYPE_RE = Regex("[a-z_]{1,32}")
private val ID_RE = Regex("[A-Za-z0-9_.:-]{1,64}")

fun isValidType(type: String): Boolean = TYPE_RE.matches(type)
fun isValidId(id: String): Boolean = ID_RE.matches(id)

/** Сбой записи; коды совпадают с `err.code` протокола, [current] — текущий документ для `err.doc`. */
class StoreException(val code: String, message: String, val current: Doc? = null) : Exception(message)
