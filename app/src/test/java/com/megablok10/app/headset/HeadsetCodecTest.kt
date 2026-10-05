package com.megablok10.app.headset

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Кадры связи с очками: точные имена полей из docs/netrun-phone-link.md («Конверт кадра»), терпимый разбор команд. */
@RunWith(RobolectricTestRunner::class)
class HeadsetCodecTest {
    private fun json(frame: HeadsetOut) = JSONObject(HeadsetCodec.encode(frame))

    @Test fun helloCarriesVersionAndCallsignButNoToken() {
        val o = json(HeadsetOut.Hello("Alice"))
        assertEquals("hello", o.getString("t"))
        assertEquals(1, o.getInt("v"))
        assertEquals("Alice", o.getString("callsign"))
        assertEquals(setOf("t", "v", "callsign"), o.keys().asSequence().toSet())
    }

    @Test fun threadsUseTheAgreedFieldNames() {
        val o = json(HeadsetOut.Threads(listOf(HeadsetThread("KEY", "DM", "Bob", "привет", 1_700_000_000, 2))))
        val item = o.getJSONArray("items").getJSONObject(0)
        assertEquals("threads", o.getString("t"))
        assertEquals(setOf("id", "kind", "title", "last_text", "last_ts", "unread"), item.keys().asSequence().toSet())
        assertEquals("привет", item.getString("last_text"))
        assertEquals(1_700_000_000L, item.getLong("last_ts"))
    }

    @Test fun messagesReplaceTheWholeThreadAndMessageCarriesOne() {
        val m = HeadsetMessage("7", "faction", false, "тест", 5, "delivered", "Bob")
        val all = json(HeadsetOut.Messages("faction", listOf(m)))
        assertEquals("messages", all.getString("t"))
        assertEquals("faction", all.getString("thread"))
        assertEquals(setOf("id", "thread", "mine", "text", "ts", "status", "from"), all.getJSONArray("items").getJSONObject(0).keys().asSequence().toSet())
        val one = json(HeadsetOut.Message(m))
        assertEquals("message", one.getString("t"))
        assertEquals("7", one.getJSONObject("msg").getString("id"))
    }

    @Test fun callCallLogAndSoundFrames() {
        val call = json(HeadsetOut.Call(HeadsetCall("in_call", "Bob", 100, true)))
        assertEquals(setOf("t", "phase", "peer", "since_ts", "muted"), call.keys().asSequence().toSet())
        assertEquals(true, call.getBoolean("muted"))
        val log = json(HeadsetOut.CallLog(listOf(HeadsetCallLogItem("Bob", "missed", 5, 0))))
        assertEquals(setOf("peer", "dir", "ts", "duration_s"), log.getJSONArray("items").getJSONObject(0).keys().asSequence().toSet())
        assertEquals("ringback", json(HeadsetOut.Sound("ringback")).getString("kind"))
    }

    @Test fun commandsFromTheHeadsetAreParsed() {
        assertEquals(HeadsetCommand.HelloAck(1), HeadsetCodec.decode("""{"t":"hello_ack","v":1}"""))
        assertEquals(HeadsetCommand.SendText("faction", "yes"), HeadsetCodec.decode("""{"t":"send_text","thread":"faction","preset":"yes"}"""))
        assertEquals(HeadsetCommand.MarkRead("K"), HeadsetCodec.decode("""{"t":"mark_read","thread":"K"}"""))
        assertEquals(HeadsetCommand.Accept, HeadsetCodec.decode("""{"t":"accept"}"""))
        assertEquals(HeadsetCommand.Decline, HeadsetCodec.decode("""{"t":"decline"}"""))
        assertEquals(HeadsetCommand.Hangup, HeadsetCodec.decode("""{"t":"hangup"}"""))
        assertEquals(HeadsetCommand.Mute(true), HeadsetCodec.decode("""{"t":"mute","on":true}"""))
        assertEquals(HeadsetCommand.StartCall("Bob"), HeadsetCodec.decode("""{"t":"start_call","peer":"Bob"}"""))
        assertEquals(HeadsetCommand.Resync, HeadsetCodec.decode("""{"t":"resync"}"""))
    }

    @Test fun unknownFieldsAreIgnoredButUnknownTypesAndBrokenFramesAreNot() {
        assertEquals(HeadsetCommand.Resync, HeadsetCodec.decode("""{"t":"resync","future":[1,2],"x":{"y":1}}"""))
        assertNull(HeadsetCodec.decode("""{"t":"teleport"}"""))
        assertNull(HeadsetCodec.decode("не json"))
        assertNull(HeadsetCodec.decode("""[1,2]"""))
        assertNull(HeadsetCodec.decode("""{"no_type":1}"""))
    }

    @Test fun commandsWithoutRequiredFieldsAreRejected() {
        assertNull(HeadsetCodec.decode("""{"t":"send_text","thread":"faction"}"""))
        assertNull(HeadsetCodec.decode("""{"t":"send_text","preset":"yes"}"""))
        assertNull(HeadsetCodec.decode("""{"t":"mark_read"}"""))
        assertNull(HeadsetCodec.decode("""{"t":"mute"}"""))
        assertNull(HeadsetCodec.decode("""{"t":"start_call"}"""))
    }

    @Test fun frameLargerThanLimitIsRejected() {
        val big = """{"t":"resync","pad":"${"x".repeat(MAX_FRAME_CHARS)}"}"""
        assertNull(HeadsetCodec.decode(big))
    }

    @Test fun presetTableMatchesTheOwnersSixPhrases() {
        assertEquals(listOf("yes", "no", "later", "callback", "hi", "cu"), HEADSET_PRESETS.keys.toList())
        assertEquals(listOf("Да", "Нет", "Позже", "Перезвоню", "Привет", "Увидимся"), HEADSET_PRESETS.values.toList())
    }
}
