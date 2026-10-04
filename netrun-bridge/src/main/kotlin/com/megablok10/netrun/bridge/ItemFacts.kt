package com.megablok10.netrun.bridge

import com.megablok10.rules.Daemon
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * Что Мост знает о предмете для правил взлома: демон из документа (поле `daemon`, а нет его — разбор `payload` тем же
 * [ItemPayloadCodec], что пишет это поле) и тир шарда или демона; рабочий ли демон сессии (протокол, раздел 5, «Рабочие и груз»).
 */
internal object ItemFacts {
    /** Демон из документа `item`; null — не демон или содержимое не разбирается. Id демона — id предмета. */
    fun daemon(item: Doc): Daemon? {
        if (VJ.str(item.data, "kind") != "DAEMON") return null
        val field = item.data[ItemDecode.DAEMON] as? JsonObject
        if (field != null) {
            val effect = DaemonEffect.entries.firstOrNull { it.name == VJ.str(field, "effect") }
            val cells = VJ.list(field, "cells")
            val level = (field["tier"] as? JsonPrimitive)?.longOrNull?.toInt()
            if (effect != null && cells.isNotEmpty() && level != null) {
                return Daemon(item.id, VJ.str(field, "name").orEmpty(), cells, Tier.fromLevel(level), effect)
            }
        }
        return VJ.str(item.data, "payload")?.let(ItemPayloadCodec::decodeDaemon)?.copy(id = item.id)
    }

    /** Тир предмета-хранилища (`shard.tier` или `daemon.tier`) по полю документа; null — поля нет (в хранилище такой не кладут). */
    fun tier(item: Doc): Tier? {
        val field = item.data[if (VJ.str(item.data, "kind") == "SHARD") ItemDecode.SHARD else ItemDecode.DAEMON] as? JsonObject ?: return null
        val level = (field["tier"] as? JsonPrimitive)?.longOrNull?.toInt() ?: return null
        return Tier.entries.firstOrNull { it.level == level }
    }

    /**
     * Рабочий ли предмет в сессии [session]: его id в `session.loaded` (сданное при входе). Сессия без `loaded` (создана до К2) —
     * по происхождению: `origin == phone:<игрок>`. Всё остальное в `deck:<s>` — груз.
     */
    fun isWorking(session: Doc, item: Doc): Boolean {
        val loaded = session.data["loaded"] as? kotlinx.serialization.json.JsonArray
        if (loaded != null) return item.id in VJ.list(session.data, "loaded")
        return VJ.str(item.data, "origin") == "phone:" + VJ.str(session.data, "runner")
    }
}
