package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject

/**
 * Проверки общего `put`/`del` (протокол, разделы 3 и 5): какие типы роли можно писать и что считается ценностью.
 * Ценности (`item`, `deck`, `session` кроме `data.world`, `node.data.eddies`) общий путь не трогает — только операции B3.
 */
internal object WriteGuard {
    private val worldTypes = setOf("node", "session", "alert")
    private val bridgeOnly = setOf("deck", "item")

    fun checkRole(role: String, type: String) {
        if (role == "world" && type !in worldTypes) throw StoreException("forbidden", "роль world не пишет тип $type")
    }

    /** [cur] — текущий документ (null при создании), [data] — новые данные (null при удалении). */
    fun checkValues(type: String, cur: Doc?, data: JsonObject?) {
        val bad = when (type) {
            in bridgeOnly -> true
            "session" -> cur == null || data == null || withoutWorld(cur.data) != withoutWorld(data)
            "node" -> cur != null && data != null && cur.data["eddies"] != data["eddies"]
            else -> false
        }
        if (bad) throw StoreException("value_field", "тип $type или его поле — ценность, нужна операция из раздела 6", cur)
    }

    private fun withoutWorld(d: JsonObject) = JsonObject(d - "world")
}
