package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import java.security.MessageDigest

/**
 * Терминал и сессия игрока (протокол, раздел 7): `terminal.auth`, `session.confirm`, `terminal.beat`.
 * Роли проверяет [BridgeServer]; здесь только данные. Каждая операция — одна транзакция хранилища.
 */
class TerminalOps(private val store: DocStore, private val clock: () -> Long = System::currentTimeMillis) {
    /** Токен сверяется по хешу из документа терминала; нет терминала или токен не тот — одинаково `bad_token`. */
    fun auth(terminal: String, token: String): Map<String, JsonElement> {
        val t = store.get(ValueOps.TERMINAL, terminal)
        val expected = t?.let { VJ.str(it.data, "token_sha256") }
        val actual = VJ.sha256Hex(token)
        if (t == null || expected == null || !MessageDigest.isEqual(expected.lowercase().toByteArray(), actual.toByteArray())) {
            throw StoreException("bad_token", "токен терминала не сошёлся")
        }
        val open = store.list(ValueOps.SESSION).firstOrNull { VJ.str(it.data, "terminal") == terminal && VJ.str(it.data, "state") != "closed" }
        return mapOf("terminal" to t.toJson(), "session" to (open?.toJson() ?: JsonNull))
    }

    /** Идемпотентна по состоянию: `pending` → `active`, уже `active` — тот же ответ, `closed` — `session_state`. */
    fun confirm(session: String, terminal: String): Map<String, JsonElement> = store.transaction { tx ->
        val s = tx.get(ValueOps.SESSION, session) ?: throw StoreException("not_found", "сессии нет")
        if (VJ.str(s.data, "terminal") != terminal) throw StoreException("bad_request", "сессия другого терминала")
        val doc = when (VJ.str(s.data, "state")) {
            "active" -> s
            "pending" -> tx.put(
                ValueOps.SESSION, s.id, s.ver,
                VJ.with(s.data, "state" to VJ.p("active"), "confirmed_at" to VJ.p(clock())),
            )
            else -> throw StoreException("session_state", "сессия закрыта", s)
        }
        mapOf("session" to doc.toJson())
    }

    /**
     * Heartbeat терминала (нужен правилу `TerminalSilentRule`, оно считает молчание по `updated`): `beat_at` меняется на
     * каждый вызов, поэтому документ обновляется всегда; необязательные [battery], [fps], [link] пишутся, если пришли.
     * Флаг `silent` не трогаем — его ведёт правило.
     */
    fun beat(terminal: String, battery: Long?, fps: Long?, link: Long?): Map<String, JsonElement> = store.transaction { tx ->
        val t = tx.get(ValueOps.TERMINAL, terminal) ?: throw StoreException("not_found", "терминала нет")
        val extra = listOfNotNull(
            battery?.let { "battery" to VJ.p(it) }, fps?.let { "fps" to VJ.p(it) }, link?.let { "link" to VJ.p(it) },
        )
        val data: JsonObject = VJ.with(t.data, "beat_at" to VJ.p(clock()), *extra.toTypedArray())
        mapOf("ver" to VJ.p(tx.put(ValueOps.TERMINAL, t.id, t.ver, data).ver))
    }
}
