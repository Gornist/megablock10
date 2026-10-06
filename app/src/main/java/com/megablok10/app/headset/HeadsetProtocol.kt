package com.megablok10.app.headset

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Протокол связи телефона с очками (Pico 4 как второй экран): JSON-кадры по одному на WebSocket-сообщение. Формат и порядок слияния —
 * docs/netrun-phone-link.md (разделы 2 и 4, ветка agent/phone-link-plan), «Конверт кадра»: объект с полем `t` и плоскими полями, поле `v` —
 * версия формата. Неизвестные поля и типы читающая сторона игнорирует; кадр больше [MAX_FRAME_CHARS] — ошибка. Новый канал отдельный: сокет
 * чата на 47100 и `WireVersion` не затронуты.
 */
const val HEADSET_PROTOCOL_VERSION = 1

/** Больше этого размера кадр не шлём и не принимаем (256 КБ по договорённости с очками). */
const val MAX_FRAME_CHARS = 256 * 1024

/** Заготовки ответа: очки присылают id, текст подставляет телефон (решение владельца 05.10.2026; единственное место таблицы на стороне приложения). */
val HEADSET_PRESETS: Map<String, String> = linkedMapOf(
    "yes" to "Да",
    "no" to "Нет",
    "later" to "Позже",
    "callback" to "Перезвоню",
    "hi" to "Привет",
    "cu" to "Увидимся",
)

/** Идентификатор общего чата фракции в кадрах; личные диалоги называются публичным ключом собеседника. */
const val HEADSET_FACTION_THREAD = "faction"

/** Диалог в списке очков. [lastTs] — unix-секунды. */
data class HeadsetThread(
    val id: String,
    val kind: String,
    val title: String,
    val lastText: String,
    val lastTs: Long,
    val unread: Int,
) {
    companion object {
        const val KIND_DM = "DM"
        const val KIND_FACTION = "FACTION"
    }
}

/** Сообщение диалога. [status] — `sent` | `delivered` | `failed`; [from] — позывной автора (в личном диалоге пуст). */
data class HeadsetMessage(
    val id: String,
    val thread: String,
    val mine: Boolean,
    val text: String,
    val ts: Long,
    val status: String,
    val from: String,
) {
    companion object {
        const val SENT = "sent"
        const val DELIVERED = "delivered"
        const val FAILED = "failed"
    }
}

data class HeadsetCall(val phase: String, val peer: String, val sinceTs: Long, val muted: Boolean) {
    companion object {
        const val IDLE = "idle"
        const val OUTGOING = "outgoing"
        const val INCOMING = "incoming"
        const val IN_CALL = "in_call"
    }
}

/** Запись журнала звонков: [dir] — `in` | `out` | `missed`. */
data class HeadsetCallLogItem(val peer: String, val dir: String, val ts: Long, val durationS: Long) {
    companion object {
        const val IN = "in"
        const val OUT = "out"
        const val MISSED = "missed"
    }
}

/** Контакт, которому можно позвонить из очков (`start_call{peer}`): [key] — публичный ключ, [title] — позывной. */
data class HeadsetContact(val key: String, val title: String)

/** Что телефон отдаёт очкам. */
sealed interface HeadsetOut {
    data class Hello(val callsign: String, val v: Int = HEADSET_PROTOCOL_VERSION) : HeadsetOut
    data class Threads(val items: List<HeadsetThread>) : HeadsetOut
    /** Полная замена истории диалога. */
    data class Messages(val thread: String, val items: List<HeadsetMessage>) : HeadsetOut
    /** Одно новое или изменившееся сообщение. */
    data class Message(val msg: HeadsetMessage) : HeadsetOut
    data class Call(val call: HeadsetCall) : HeadsetOut
    data class CallLog(val items: List<HeadsetCallLogItem>) : HeadsetOut
    /** Контакты для выбора, кому позвонить (кадр `contacts`: добавлен очками в контрактной фикстуре `netrun/tests/fixtures/phone_frames.json`). */
    data class Contacts(val items: List<HeadsetContact>) : HeadsetOut
    /** [kind]: ring | ringback | message | stop. */
    data class Sound(val kind: String) : HeadsetOut
    /** Голос звонка в очках включён ([on]) или выключен; [rate] — частота бинарных кадров звука (срез 3). */
    data class Voice(val on: Boolean, val rate: Int = HEADSET_VOICE_RATE) : HeadsetOut
}

/** Что очки просят у телефона. */
sealed interface HeadsetCommand {
    data class HelloAck(val v: Int) : HeadsetCommand
    data class SendText(val thread: String, val preset: String) : HeadsetCommand
    data class MarkRead(val thread: String) : HeadsetCommand
    data object Accept : HeadsetCommand
    data object Decline : HeadsetCommand
    data object Hangup : HeadsetCommand
    data class Mute(val on: Boolean) : HeadsetCommand
    data class StartCall(val peer: String) : HeadsetCommand
    data object Resync : HeadsetCommand
    /** Очки готовы к голосу звонка (микрофон и динамик открыты) или отказались/сняты ([on] = false). */
    data class VoiceReady(val on: Boolean) : HeadsetCommand
}

/** Кодек кадров. Разбор терпимый: мусор, неизвестный тип, нехватка обязательных полей — `null`, а не исключение. */
object HeadsetCodec {
    fun encode(frame: HeadsetOut): String = when (frame) {
        is HeadsetOut.Hello -> JSONObject().put("t", "hello").put("v", frame.v).put("callsign", frame.callsign)
        is HeadsetOut.Threads -> JSONObject().put("t", "threads").put("items", JSONArray(frame.items.map(::threadJson)))
        is HeadsetOut.Messages -> JSONObject().put("t", "messages").put("thread", frame.thread).put("items", JSONArray(frame.items.map(::messageJson)))
        is HeadsetOut.Message -> JSONObject().put("t", "message").put("msg", messageJson(frame.msg))
        is HeadsetOut.Call -> JSONObject().put("t", "call").put("phase", frame.call.phase).put("peer", frame.call.peer)
            .put("since_ts", frame.call.sinceTs).put("muted", frame.call.muted)
        is HeadsetOut.CallLog -> JSONObject().put("t", "call_log").put("items", JSONArray(frame.items.map(::callLogJson)))
        is HeadsetOut.Contacts -> JSONObject().put("t", "contacts").put("items", JSONArray(frame.items.map { JSONObject().put("key", it.key).put("title", it.title) }))
        is HeadsetOut.Sound -> JSONObject().put("t", "sound").put("kind", frame.kind)
        is HeadsetOut.Voice -> JSONObject().put("t", "voice").put("on", frame.on).put("rate", frame.rate)
    }.toString()

    fun decode(text: String): HeadsetCommand? {
        if (text.length > MAX_FRAME_CHARS) return null
        val o = try { JSONObject(text) } catch (e: JSONException) { return null }
        return when (o.optString("t")) {
            "hello_ack" -> HeadsetCommand.HelloAck(o.optInt("v", 0))
            "send_text" -> pair(o, "thread", "preset")?.let { (thread, preset) -> HeadsetCommand.SendText(thread, preset) }
            "mark_read" -> o.optString("thread").takeIf { it.isNotEmpty() }?.let(HeadsetCommand::MarkRead)
            "accept" -> HeadsetCommand.Accept
            "decline" -> HeadsetCommand.Decline
            "hangup" -> HeadsetCommand.Hangup
            "mute" -> if (o.has("on")) HeadsetCommand.Mute(o.optBoolean("on")) else null
            "start_call" -> o.optString("peer").takeIf { it.isNotEmpty() }?.let(HeadsetCommand::StartCall)
            "resync" -> HeadsetCommand.Resync
            "voice_ready" -> if (o.has("on")) HeadsetCommand.VoiceReady(o.optBoolean("on")) else null
            else -> null
        }
    }

    private fun pair(o: JSONObject, a: String, b: String): Pair<String, String>? {
        val x = o.optString(a)
        val y = o.optString(b)
        return if (x.isEmpty() || y.isEmpty()) null else x to y
    }

    private fun threadJson(t: HeadsetThread) = JSONObject().put("id", t.id).put("kind", t.kind).put("title", t.title)
        .put("last_text", t.lastText).put("last_ts", t.lastTs).put("unread", t.unread)

    private fun messageJson(m: HeadsetMessage) = JSONObject().put("id", m.id).put("thread", m.thread).put("mine", m.mine)
        .put("text", m.text).put("ts", m.ts).put("status", m.status).put("from", m.from)

    private fun callLogJson(c: HeadsetCallLogItem) = JSONObject().put("peer", c.peer).put("dir", c.dir).put("ts", c.ts).put("duration_s", c.durationS)
}
