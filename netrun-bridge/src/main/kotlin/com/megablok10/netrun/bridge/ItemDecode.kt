package com.megablok10.netrun.bridge

import com.megablok10.rules.ItemPayloadCodec
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Разобранное содержимое предмета для сервера мира (протокол Моста, документ `item`): `payload` остаётся байт в байт как в
 * карточке, рядом пишется `daemon` ({effect, tier, name, cells}) или `shard` ({tier, title, decrypted}). Сервер мира не знает
 * формата карточки и строит демона из этих полей. Тело шарда (`body`) и сумма не выносятся — Сеть их не читает.
 */
object ItemDecode {
    const val DAEMON = "daemon"
    const val SHARD = "shard"

    /** Поля для документа `item` по `kind` и `payload`; пусто, если содержимое не разобралось (или kind другой). */
    fun fields(kind: String?, payload: String?): Map<String, JsonObject> {
        payload ?: return emptyMap()
        return when (kind) {
            "DAEMON" -> ItemPayloadCodec.decodeDaemon(payload)?.let { d ->
                mapOf(
                    DAEMON to VJ.obj(
                        "effect" to VJ.p(d.effect.name), "tier" to VJ.p(d.tier.level.toLong()), "name" to VJ.p(d.name),
                        "cells" to JsonArray(d.sequence.map { JsonPrimitive(it) }),
                    ),
                )
            }
            "SHARD" -> ItemPayloadCodec.decodeShard(payload)?.let { s ->
                mapOf(SHARD to VJ.obj("tier" to VJ.p(s.tier.toLong()), "title" to VJ.p(s.title), "decrypted" to VJ.p(s.decrypted)))
            }
            else -> null
        } ?: emptyMap()
    }

    /** [data] с добавленным `daemon`/`shard`, если поля ещё нет и payload разбирается; иначе null (менять нечего). */
    fun enrich(data: JsonObject): JsonObject? {
        val field = if (VJ.str(data, "kind") == "SHARD") SHARD else DAEMON
        if (field in data) return null
        val add = fields(VJ.str(data, "kind"), VJ.str(data, "payload"))
        return if (add.isEmpty()) null else JsonObject(data + add)
    }

    /** Дописывает поле предметам, у которых его нет (документы, принятые до M5b). Возвращает число обновлённых. */
    fun backfill(store: DocStore): Int = store.list(ValueOps.ITEM).count { d ->
        val next = enrich(d.data) ?: return@count false
        store.put(ValueOps.ITEM, d.id, d.ver, next)
        true
    }
}
