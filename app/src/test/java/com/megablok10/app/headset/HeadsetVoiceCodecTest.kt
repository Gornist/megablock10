package com.megablok10.app.headset

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Бинарные кадры голоса и JSON-кадры `voice`/`voice_ready`. */
@RunWith(RobolectricTestRunner::class)
class HeadsetVoiceCodecTest {
    @Test fun binaryFrameRoundTrips() {
        val pcm = shortArrayOf(0, 1, -1, 32767, -32768, 1234)
        val bytes = HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_MIC, 7, pcm)
        assertEquals(5 + pcm.size * 2, bytes.size)
        assertEquals(VoiceFrame(HeadsetVoiceCodec.TYPE_MIC, 7, pcm), HeadsetVoiceCodec.decode(bytes))
    }

    @Test fun layoutIsTypeThenLittleEndianSeqThenLittleEndianSamples() {
        val bytes = HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_MIC, 7, shortArrayOf(0x0102, -2))
        assertEquals(listOf<Byte>(1, 7, 0, 0, 0, 0x02, 0x01, -2, -1), bytes.toList())
    }

    @Test fun seqIsUnsigned32Bit() {
        val bytes = HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_PLAYBACK, 0xFFFF_FFFFL, ShortArray(2))
        assertEquals(0xFFFF_FFFFL, HeadsetVoiceCodec.decode(bytes)!!.seq)
    }

    @Test fun fullChunkFitsTheLimit() {
        val bytes = HeadsetVoiceCodec.encode(HeadsetVoiceCodec.TYPE_MIC, 0, ShortArray(HEADSET_VOICE_CHUNK))
        assertEquals(HEADSET_VOICE_CHUNK, HeadsetVoiceCodec.decode(bytes)!!.pcm.size)
    }

    @Test fun malformedBinaryFramesAreRejected() {
        assertNull("короче заголовка", HeadsetVoiceCodec.decode(byteArrayOf(1, 0, 0)))
        assertNull("нечётная длина звука", HeadsetVoiceCodec.decode(byteArrayOf(1, 0, 0, 0, 0, 5)))
        assertNull("неизвестный тип", HeadsetVoiceCodec.decode(byteArrayOf(9, 0, 0, 0, 0)))
        assertNull("слишком длинный", HeadsetVoiceCodec.decode(ByteArray(5 + 4098).also { it[0] = 1 }))
        assertNotNull("пустой звук допустим", HeadsetVoiceCodec.decode(byteArrayOf(1, 0, 0, 0, 0)))
    }

    @Test fun voiceFrameEncodesAsAgreed() {
        val o = org.json.JSONObject(HeadsetCodec.encode(HeadsetOut.Voice(true)))
        assertEquals("voice", o.getString("t"))
        assertTrue(o.getBoolean("on"))
        assertEquals(44_100, o.getInt("rate"))
        assertEquals(false, org.json.JSONObject(HeadsetCodec.encode(HeadsetOut.Voice(false))).getBoolean("on"))
    }

    @Test fun voiceReadyIsParsedAndNeedsTheOnField() {
        assertEquals(HeadsetCommand.VoiceReady(true), HeadsetCodec.decode("""{"t":"voice_ready","on":true}"""))
        assertEquals(HeadsetCommand.VoiceReady(false), HeadsetCodec.decode("""{"t":"voice_ready","on":false}"""))
        assertNull(HeadsetCodec.decode("""{"t":"voice_ready"}"""))
    }
}
