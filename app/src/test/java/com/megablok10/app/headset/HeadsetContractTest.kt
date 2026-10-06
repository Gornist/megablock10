package com.megablok10.app.headset

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Контракт с очками: канонические кадры из `netrun/tests/fixtures/phone_frames.json` (их читает и сторона очков). Кадры телефона → очкам,
 * собранные кодеком приложения из тех же данных, должны совпасть с фикстурой до поля; команды очков → телефону из фикстуры должны разбираться.
 * Упало после правки фикстуры — формат поменяли на одной стороне: согласовать с сессией Godot, а не подгонять тест.
 */
@RunWith(RobolectricTestRunner::class)
class HeadsetContractTest {
    private val fixture: JSONObject by lazy {
        // Рабочий каталог unit-тестов Gradle — каталог модуля app/.
        val file = File("../netrun/tests/fixtures/phone_frames.json")
        assertTrue("нет файла контракта ${file.absolutePath}", file.exists())
        JSONObject(file.readText())
    }
    private val phone get() = fixture.getJSONObject("phone_to_glasses")
    private val glasses get() = fixture.getJSONObject("glasses_to_phone")

    private fun items(o: JSONObject): List<JSONObject> = o.getJSONArray("items").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }

    private fun thread(o: JSONObject) = HeadsetThread(o.getString("id"), o.getString("kind"), o.getString("title"), o.getString("last_text"), o.getLong("last_ts"), o.getInt("unread"))

    private fun message(o: JSONObject) = HeadsetMessage(
        o.getString("id"), o.getString("thread"), o.getBoolean("mine"), o.getString("text"), o.getLong("ts"), o.getString("status"), o.optString("from"),
    )

    /** Кодек приложения даёт тот же JSON, что и фикстура (имена, типы, лишних полей нет). */
    private fun assertSame(name: String, frame: HeadsetOut) {
        val expected = phone.getJSONObject(name)
        val actual = JSONObject(HeadsetCodec.encode(frame))
        assertEquals("кадр «$name» разошёлся с контрактом", canon(expected), canon(actual))
    }

    /** Канонический вид JSON для сравнения: ключи по алфавиту, числа без различия int/long (в Android `org.json` нет `similar`). */
    private fun canon(v: Any?): String = when (v) {
        is JSONObject -> v.keys().asSequence().sorted().joinToString(",", "{", "}") { "\"$it\":" + canon(v.get(it)) }
        is org.json.JSONArray -> (0 until v.length()).joinToString(",", "[", "]") { canon(v.get(it)) }
        is String -> "\"$v\""
        else -> v.toString()
    }

    @Test fun helloAndThreadsAndMessagesMatchTheFixture() {
        assertSame("hello", HeadsetOut.Hello(phone.getJSONObject("hello").getString("callsign")))
        assertSame("threads", HeadsetOut.Threads(items(phone.getJSONObject("threads")).map(::thread)))
        for (name in listOf("messages_lis", "messages_faction")) {
            val o = phone.getJSONObject(name)
            assertSame(name, HeadsetOut.Messages(o.getString("thread"), items(o).map(::message)))
        }
        for (name in listOf("message_incoming", "message_faction", "message_status")) {
            assertSame(name, HeadsetOut.Message(message(phone.getJSONObject(name).getJSONObject("msg"))))
        }
    }

    @Test fun callFramesMatchTheFixture() {
        for (name in listOf("call_idle", "call_outgoing", "call_incoming", "call_in_call")) {
            val o = phone.getJSONObject(name)
            assertSame(name, HeadsetOut.Call(HeadsetCall(o.getString("phase"), o.getString("peer"), o.getLong("since_ts"), o.getBoolean("muted"))))
        }
        val log = items(phone.getJSONObject("call_log")).map { HeadsetCallLogItem(it.getString("peer"), it.getString("dir"), it.getLong("ts"), it.getLong("duration_s")) }
        assertSame("call_log", HeadsetOut.CallLog(log))
    }

    @Test fun contactsAndSoundFramesMatchTheFixture() {
        assertSame("contacts", HeadsetOut.Contacts(items(phone.getJSONObject("contacts")).map { HeadsetContact(it.getString("key"), it.getString("title")) }))
        for (kind in listOf("ring", "ringback", "message", "stop")) assertSame("sound_$kind", HeadsetOut.Sound(kind))
    }

    @Test fun voiceFramesMatchTheFixture() {
        assertSame("voice_on", HeadsetOut.Voice(true, phone.getJSONObject("voice_on").getInt("rate")))
        assertSame("voice_off", HeadsetOut.Voice(false))
    }

    /** Бинарные кадры голоса: раскладка `[тип][seq LE][int16 LE]` из раздела `binary` фикстуры сверяется в обе стороны. */
    @Test fun binaryVoiceFramesMatchTheFixture() {
        val binary = fixture.getJSONObject("binary")
        val samples = binary.getJSONArray("samples").let { a -> ShortArray(a.length()) { a.getInt(it).toShort() } }
        val seq = binary.getLong("seq")
        for ((name, type) in listOf("voice_mic_hex" to HeadsetVoiceCodec.TYPE_MIC, "voice_peer_hex" to HeadsetVoiceCodec.TYPE_PLAYBACK)) {
            val hex = binary.getString(name)
            val bytes = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
            assertEquals("$name: разбор", VoiceFrame(type, seq, samples), HeadsetVoiceCodec.decode(bytes))
            assertEquals("$name: сборка", hex, HeadsetVoiceCodec.encode(type, seq, samples).joinToString("") { "%02x".format(it) })
        }
    }

    @Test fun everyFixtureFrameOfThePhoneHasATest() {
        val covered = setOf(
            "hello", "threads", "messages_lis", "messages_faction", "message_incoming", "message_faction", "message_status",
            "call_idle", "call_outgoing", "call_incoming", "call_in_call", "call_log", "contacts", "sound_ring", "sound_ringback", "sound_message", "sound_stop",
            "voice_on", "voice_off",
        )
        val all = phone.keys().asSequence().toSet()
        assertEquals("в фикстуре появились кадры, которых нет в проверке: ${all - covered}", emptySet<String>(), all - covered)
    }

    @Test fun everyCommandInTheFixtureIsUnderstood() {
        val key = glasses.getJSONObject("send_text").getString("thread")
        assertEquals(HeadsetCommand.HelloAck(1), HeadsetCodec.decode(glasses.getJSONObject("hello_ack").toString()))
        assertEquals(HeadsetCommand.SendText(key, "callback"), HeadsetCodec.decode(glasses.getJSONObject("send_text").toString()))
        assertEquals(HeadsetCommand.MarkRead(key), HeadsetCodec.decode(glasses.getJSONObject("mark_read").toString()))
        assertEquals(HeadsetCommand.Accept, HeadsetCodec.decode(glasses.getJSONObject("accept").toString()))
        assertEquals(HeadsetCommand.Decline, HeadsetCodec.decode(glasses.getJSONObject("decline").toString()))
        assertEquals(HeadsetCommand.Hangup, HeadsetCodec.decode(glasses.getJSONObject("hangup").toString()))
        assertEquals(HeadsetCommand.Mute(true), HeadsetCodec.decode(glasses.getJSONObject("mute").toString()))
        assertEquals(HeadsetCommand.StartCall(glasses.getJSONObject("start_call").getString("peer")), HeadsetCodec.decode(glasses.getJSONObject("start_call").toString()))
        assertEquals(HeadsetCommand.Resync, HeadsetCodec.decode(glasses.getJSONObject("resync").toString()))
        assertEquals(HeadsetCommand.VoiceReady(true), HeadsetCodec.decode(glasses.getJSONObject("voice_ready_on").toString()))
        assertEquals(HeadsetCommand.VoiceReady(false), HeadsetCodec.decode(glasses.getJSONObject("voice_ready_off").toString()))
        assertEquals(11, glasses.length())
    }
}
