package com.megablok10.netrun.bridge

import com.megablok10.kit.crypto.Ecdsa
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Кому отдают предмет по `op.give_item` (протокол, 6.7): ровно один из двух видов.
 *
 * [Session] — нетраннер в Сети (его деке прибавится предмет); [Phone] — телефон по ключу (обычный base64 SPKI), предмет уходит
 * карточкой Handover от ключа мира и покидает забег целиком.
 */
sealed interface GiveTarget {
    data class Session(val id: String) : GiveTarget

    data class Phone(val key: String) : GiveTarget
}

/**
 * `op.give_item` — отдать предмет из груза сессии [session] (протокол, 6.7; дизайн деки §9.2). Отдаётся только ГРУЗ: защищённый
 * демон — `protected_item`, рабочий демон (id в `session.loaded`) — `loaded_item`; эдди не отдаются.
 *
 * Одна транзакция: `item.owner` → `deck:<получатель>` (и `deck.items` обеих сессий) либо → `outbox:<ключ>` с `handover: PENDING` и
 * `out_transfer` (карточка от ключа мира кладётся в `Outbox` после коммита, как в `op.issue_to_phone`). `payload` и `origin` не
 * меняются. [ver] — версия предмета, которую видел сервер мира; `rid` = `give:<сессия>:<предмет>:<ver>`: предмет может вернуться
 * (A → B → A) и уйти снова, и без версии второй раз сработал бы повтор старого ответа.
 *
 * Идемпотентность — по `rid` ([ValueOps.execute]): повтор вернёт сохранённый ответ, вторых карточек не будет.
 */
fun ValueOps.giveItem(caller: Caller, rid: String, session: String, item: String, ver: Long, to: GiveTarget): OpResult {
    GiveCheck.validate(session, item, ver, to)
    val params = VJ.obj(
        "op" to VJ.p("give_item"), "session" to VJ.p(session), "item" to VJ.p(item), "ver" to VJ.p(ver),
        "to_session" to VJ.p((to as? GiveTarget.Session)?.id), "to_phone" to VJ.p((to as? GiveTarget.Phone)?.key),
    )
    return execute(caller, "op.give_item", rid, params) { tx, ctx -> GiveTx(this, tx, ctx, caller, rid, session, item, ver, to).run() }
}

/** Проверки запроса без документов: все — `bad_request`, не сохраняются по `rid` (ошибка кода сервера мира). */
internal object GiveCheck {
    fun validate(session: String, item: String, ver: Long, to: GiveTarget) {
        if (session.isEmpty() || item.isEmpty()) bad("нужны session и item")
        if (ver < 1) bad("ver — версия предмета, целое от 1")
        when (to) {
            is GiveTarget.Session -> if (to.id.isEmpty() || to.id == session) bad("to_session — другая сессия")
            is GiveTarget.Phone -> if (!isCanonicalKey(to.key)) bad("to_phone не разбирается как ключ телефона")
        }
    }

    /** Ключ телефона — SPKI в каноничном base64 (как `Ecdsa.encodeKey`): иначе `outbox:<ключ>` разошёлся бы с документом `runner`. */
    fun isCanonicalKey(key: String): Boolean =
        key.isNotEmpty() && runCatching { Ecdsa.encodeKey(Ecdsa.decodePublicKey(key)) == key }.getOrDefault(false)

    private fun bad(msg: String): Nothing = throw StoreException("bad_request", msg)
}

/** Тело транзакции `op.give_item`; порядок проверок — как в таблице отказов протокола, 6.7. */
@Suppress("LongParameterList")
private class GiveTx(
    private val ops: ValueOps,
    private val tx: DocStore.Tx,
    private val ctx: ValueOps.Ctx,
    private val caller: Caller,
    private val rid: String,
    private val session: String,
    private val itemId: String,
    private val ver: Long,
    private val to: GiveTarget,
) {
    fun run(): JsonObject {
        val sender = tx.get(ValueOps.SESSION, session) ?: throw StoreException("not_found", "сессии нет")
        val doc = tx.get(ValueOps.ITEM, itemId) ?: throw StoreException("not_found", "предмета нет")
        val receiver = (to as? GiveTarget.Session)?.let { tx.get(ValueOps.SESSION, it.id) ?: throw StoreException("not_found", "сессии-получателя нет") }
        checkRequest(sender, doc)
        checkStates(sender, receiver)
        if (VJ.str(doc.data, "owner") != "deck:$session") ops.fail("wrong_owner", "предмет не в деке сессии", doc)
        if (doc.ver != ver) ops.fail("version_conflict", "версия ${doc.ver}, а не $ver", doc)
        if (VJ.bool(doc.data, "protected")) ops.fail("protected_item", "защищённого демона нельзя отдать другому игроку", doc)
        if (ItemFacts.isWorking(sender, doc)) ops.fail("loaded_item", "рабочий демон нужен забегу, отдать можно только груз", doc)
        return when (to) {
            is GiveTarget.Session -> toDeck(doc, to.id)
            is GiveTarget.Phone -> toPhone(doc, to.key)
        }
    }

    /** `bad_request` по документам: вид предмета и «свой» телефон. */
    private fun checkRequest(sender: Doc, doc: Doc) {
        if ((VJ.str(doc.data, "kind") ?: "") !in GIVE_KINDS) throw StoreException("bad_request", "отдать можно только SHARD или DAEMON")
        if (to is GiveTarget.Phone && to.key == VJ.str(sender.data, "runner")) throw StoreException("bad_request", "на свой телефон отдавать нельзя")
    }

    /** Отправитель и получатель-нетраннер: `active` и не в исходе (`world.finish`). Сохраняется по `rid`. */
    private fun checkStates(sender: Doc, receiver: Doc?) {
        for (s in listOfNotNull(sender, receiver)) {
            if (VJ.str(s.data, "state") != "active") ops.fail("session_state", "сессия ${s.id} не active", s)
            if (finishing(s)) ops.fail("session_state", "у сессии ${s.id} идёт исход", s)
        }
    }

    private fun finishing(s: Doc): Boolean {
        val finish = (s.data["world"] as? JsonObject)?.get("finish")
        return finish != null && finish !is JsonNull && !(finish is JsonPrimitive && finish.content.isEmpty())
    }

    private fun toDeck(doc: Doc, receiver: String): JsonObject {
        val from = ops.loadDeck(tx, session)
        val into = ops.loadDeck(tx, receiver)
        val moved = tx.put(ValueOps.ITEM, doc.id, doc.ver, VJ.with(doc.data, "owner" to VJ.p("deck:$receiver")))
        ops.putDeckItems(tx, from, ops.deckItems(from) - doc.id)
        ops.putDeckItems(tx, into, (ops.deckItems(into) + doc.id).distinct())
        return VJ.obj("item" to VJ.docJson(moved), "to" to VJ.p("deck:$receiver"), "transfer" to JsonNull)
    }

    private fun toPhone(doc: Doc, key: String): JsonObject {
        val from = ops.loadDeck(tx, session)
        val transfer = ops.toOutbox(tx, ctx, caller.namespace, rid, key, doc)
        ops.putDeckItems(tx, from, ops.deckItems(from) - doc.id)
        val moved = tx.get(ValueOps.ITEM, doc.id) ?: throw StoreException("internal", "предмет пропал в транзакции")
        return VJ.obj("item" to VJ.docJson(moved), "to" to VJ.p("outbox:$key"), "transfer" to VJ.p(transfer))
    }

    private companion object {
        val GIVE_KINDS = setOf("SHARD", "DAEMON")
    }
}
