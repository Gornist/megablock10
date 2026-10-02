package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/** Разбор сообщений `op.*`, `run.finish`, `session.*`, `terminal.*` и ответ по протоколу (разделы 6 и 7); роли — внутри [ValueOps]/[TerminalOps]. */
internal class OpRouter(private val ops: ValueOps, private val terminals: TerminalOps, private val master: MasterOps) {
    fun handle(caller: Caller, op: String, msg: JsonObject): Map<String, JsonElement> {
        val role = caller.role
        return when (op) {
            "op.submit_deck" -> opReply(
                ops.submitDeck(
                    caller, req(msg, "rid"), req(msg, "runner"), req(msg, "callsign"), req(msg, "terminal"),
                    strings(msg, "items"), req(msg, "protected"),
                ),
            )
            "op.take_from_node" -> opReply(
                ops.takeFromNode(caller, req(msg, "rid"), req(msg, "session"), req(msg, "node"), msg["item"].string(), msg["eddies"].long() ?: 0L),
            )
            "op.leave_in_node" -> opReply(ops.leaveInNode(caller, req(msg, "rid"), req(msg, "session"), req(msg, "node"), req(msg, "item")))
            "op.issue_to_phone" -> opReply(
                ops.issueToPhone(
                    caller, req(msg, "rid"), req(msg, "runner"), if (msg["items"] == null) emptyList() else strings(msg, "items"),
                    msg["eddies"].long() ?: 0L, msg["reason"].string().orEmpty(),
                ),
            )
            "run.finish" -> opReply(
                ops.finishRun(
                    caller, req(msg, "rid"), req(msg, "session"), req(msg, "outcome"), req(msg, "node"),
                    (msg["disconnect"] as? JsonPrimitive)?.booleanOrNull ?: false, moves(msg),
                ),
            )
            "session.abort" -> opReply(ops.abortSession(caller, req(msg, "session"), msg["reason"].string().orEmpty()))
            "terminal.auth" -> {
                if (role == Role.MASTER) throw StoreException("forbidden", "роли master операция $op не разрешена")
                terminals.auth(req(msg, "terminal"), req(msg, "token"))
            }
            "session.confirm" -> {
                if (role == Role.MASTER) throw StoreException("forbidden", "роли master операция $op не разрешена")
                terminals.confirm(req(msg, "session"), req(msg, "terminal"))
            }
            "terminal.beat" -> {
                if (role == Role.MASTER) throw StoreException("forbidden", "роли master операция $op не разрешена")
                terminals.beat(req(msg, "terminal"), msg["battery"].long(), msg["fps"].long(), msg["link"].long())
            }
            else -> if (op.startsWith("master.") || op == "net.query") handleMaster(caller, op, msg) else throw StoreException("bad_request", "неизвестный op: $op")
        }
    }

    /** Ручные операции мастера и канал «запрос к Сети» (протокол, раздел 6a); роль проверяет [MasterOps]. */
    private fun handleMaster(caller: Caller, op: String, msg: JsonObject): Map<String, JsonElement> = when (op) {
        "master.pause" -> master.pause(caller, flag(msg, "on"), msg["node"].string())
        "master.link" -> master.setVenueLink(caller, flag(msg, "on"))
        "master.goal" -> master.setGoal(caller, req(msg, "node"), req(msg, "kind"), msg["value"].long(), msg["in_s"].long(), msg["deadline"].long())
        "master.goal_clear" -> master.clearGoal(caller, req(msg, "node"))
        "master.gate" -> master.gate(req(msg, "kind"), req(msg, "ref"), msg["node"].string(), msg["summary"].string() ?: req(msg, "kind"))
        "master.decide" -> master.decide(
            caller, req(msg, "req"),
            Decision.parse(msg["decision"].string()) ?: throw StoreException("bad_request", "decision: approve или deny"),
        )
        "master.template_apply" -> master.applyTemplate(caller, req(msg, "template"), if (msg["nodes"] == null) emptyList() else strings(msg, "nodes"))
        "master.reply" -> master.reply(caller, req(msg, "query"), req(msg, "mid"), req(msg, "text"))
        "net.query" -> master.ask(caller, msg["query"].string(), req(msg, "runner"), req(msg, "mid"), req(msg, "text"))
        else -> throw StoreException("bad_request", "неизвестный op: $op")
    }

    private fun flag(msg: JsonObject, key: String): Boolean =
        (msg[key] as? JsonPrimitive)?.booleanOrNull ?: throw StoreException("bad_request", "$key — true или false")

    private fun req(msg: JsonObject, key: String): String =
        msg[key].string() ?: throw StoreException("bad_request", "нужен $key")

    private fun strings(msg: JsonObject, key: String): List<String> {
        val arr = msg[key] as? JsonArray ?: throw StoreException("bad_request", "$key — массив строк")
        return arr.map { it.string() ?: throw StoreException("bad_request", "$key — массив строк") }
    }

    private fun moves(msg: JsonObject): List<Move> {
        val arr = msg["moves"] as? JsonArray ?: throw StoreException("bad_request", "moves — массив")
        return arr.map { e ->
            val o = e as? JsonObject ?: throw StoreException("bad_request", "move — объект")
            val to = when (o["to"].string()) {
                "phone" -> MoveTo.PHONE
                "node" -> MoveTo.NODE
                "burned" -> MoveTo.BURNED
                else -> throw StoreException("bad_request", "to: phone, node или burned")
            }
            Move(req(o, "item"), to)
        }
    }

    /** Ответ [OpResult] по протоколу: успех — поля ответа и `replayed`, доменная ошибка (тоже сохранённая по rid) — `err` с кодом и документом. */
    private fun opReply(r: OpResult): Map<String, JsonElement> {
        if (!r.ok) throw StoreException(r.code ?: "internal", VJ.str(r.body, "msg") ?: "", r.doc?.let(::docOf))
        return buildMap {
            put("replayed", JsonPrimitive(r.replayed))
            putAll(r.body)
        }
    }

    private fun docOf(j: JsonObject) = Doc(
        VJ.str(j, "type").orEmpty(), VJ.str(j, "id").orEmpty(), VJ.lng(j, "ver"), VJ.lng(j, "created"), VJ.lng(j, "updated"),
        j["data"] as? JsonObject ?: JsonObject(emptyMap()),
    )
}
