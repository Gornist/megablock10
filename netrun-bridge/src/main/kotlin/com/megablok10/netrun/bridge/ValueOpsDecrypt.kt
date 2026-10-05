package com.megablok10.netrun.bridge

import com.megablok10.rules.DecryptRules
import com.megablok10.rules.ItemPayloadCodec
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `op.decrypt_item` — расшифровать шард в деке сессии [session] (протокол, 6.8; дизайн деки §3.1). Успех мини-игры решает сервер мира,
 * Мост ему доверяет, как `op.take_from_node`; здесь проверяются только владелец, версия и наличие рабочего DECRYPT нужного тира.
 *
 * Единственная операция, которая меняет `payload`: флаг «расшифрован» (поле с индексом 9) становится `1`, остальные байты строки
 * остаются как были (даже поля будущих версий) — поэтому перекодирование не `decodeShard + encodeShard`. Владелец, `origin`,
 * `protected` и поля передач не меняются: повтор входящей карточки отсекается по прежнему `in_transfer`.
 *
 * Идемпотентность — по `rid` ([ValueOps.execute]); [ver] — версия предмета, которую видел сервер мира (как в `op.give_item`).
 * Расшифровка в Сети коллектору отдельной записью не пишется: владелец предмета не меняется (решение владельца).
 */
fun ValueOps.decryptItem(caller: Caller, rid: String, session: String, item: String, ver: Long): OpResult {
    if (session.isEmpty() || item.isEmpty()) throw StoreException("bad_request", "нужны session и item")
    if (ver < 1) throw StoreException("bad_request", "ver — версия предмета, целое от 1")
    val params = VJ.obj("op" to VJ.p("decrypt_item"), "session" to VJ.p(session), "item" to VJ.p(item), "ver" to VJ.p(ver))
    return execute(caller, "op.decrypt_item", rid, params) { tx, _ -> DecryptTx(this, tx, session, item, ver).run() }
}

/** Индекс поля `decrypted` в строке `payload` шарда (`ItemPayloadCodec.encodeShard`). */
private const val DECRYPTED_FIELD = 9

/** Тело транзакции `op.decrypt_item`; порядок проверок — как в таблице отказов протокола, 6.8. */
private class DecryptTx(
    private val ops: ValueOps,
    private val tx: DocStore.Tx,
    private val session: String,
    private val itemId: String,
    private val ver: Long,
) {
    fun run(): JsonObject {
        val s = tx.get(ValueOps.SESSION, session) ?: throw StoreException("not_found", "сессии нет")
        val doc = tx.get(ValueOps.ITEM, itemId) ?: throw StoreException("not_found", "предмета нет")
        val payload = VJ.str(doc.data, "payload").orEmpty()
        val shard = ItemPayloadCodec.decodeShard(payload)
        if (VJ.str(doc.data, "kind") != "SHARD" || shard == null) throw StoreException("bad_request", "расшифровать можно только разбираемый SHARD")
        if (VJ.str(s.data, "state") != "active") ops.fail("session_state", "сессия не active", s)
        if (finishing(s)) ops.fail("session_state", "у сессии идёт исход", s)
        if (VJ.str(doc.data, "owner") != "deck:$session") ops.fail("wrong_owner", "предмет не в деке сессии", doc)
        if (doc.ver != ver) ops.fail("version_conflict", "версия ${doc.ver}, а не $ver", doc)
        if (decrypters(s).let { DecryptRules.bestDecrypter(it, shard.tier) } == null) {
            ops.fail("no_decrypter", "нет рабочего DECRYPT тира ${shard.tier} и выше", doc)
        }
        if (!shard.decryptAction || shard.decrypted) return reply(false, shard.title, shard.body, doc)
        val next = reencode(payload, shard)
        val moved = tx.put(ValueOps.ITEM, doc.id, doc.ver, VJ.with(doc.data, "payload" to VJ.p(next), "shard" to shardField(doc, next)))
        return reply(true, shard.title, shard.body, moved)
    }

    private fun finishing(s: Doc): Boolean {
        val finish = (s.data["world"] as? JsonObject)?.get("finish")
        return finish != null && finish !is JsonNull && !(finish is JsonPrimitive && finish.content.isEmpty())
    }

    /** Рабочие демоны сессии, которые лежат в её деке (`session.loaded`; нет поля — по происхождению, как [ItemFacts.isWorking]). */
    private fun decrypters(s: Doc) = ops.store.list(ValueOps.ITEM).filter { VJ.str(it.data, "owner") == "deck:$session" && ItemFacts.isWorking(s, it) }
        .mapNotNull(ItemFacts::daemon)

    /** Поле 9 := `1`, остальное — байт в байт; результат обязан разобраться тем же кодеком с единственной разницей `decrypted`. */
    private fun reencode(payload: String, before: com.megablok10.rules.ShardPayload): String {
        val parts = payload.split("|").toMutableList()
        parts[DECRYPTED_FIELD] = "1"
        val next = parts.joinToString("|")
        if (ItemPayloadCodec.decodeShard(next) != before.copy(decrypted = true)) throw StoreException("internal", "перекодирование шарда разошлось")
        return next
    }

    /** `shard` документа: `decrypted := true`, `encrypted := false`; поля нет (документ старше M5b) — собирается заново. */
    private fun shardField(doc: Doc, payload: String): JsonObject {
        val old = doc.data[ItemDecode.SHARD] as? JsonObject ?: ItemDecode.fields("SHARD", payload)[ItemDecode.SHARD] ?: VJ.obj()
        return VJ.with(old, "decrypted" to VJ.p(true), "encrypted" to VJ.p(false))
    }

    private fun reply(changed: Boolean, title: String, body: String, item: Doc) =
        VJ.obj("changed" to VJ.p(changed), "title" to VJ.p(title), "body" to VJ.p(body), "item" to VJ.docJson(item))
}
