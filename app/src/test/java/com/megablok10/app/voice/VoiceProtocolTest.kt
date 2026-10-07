package com.megablok10.app.voice

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Формат MB10VOICE v1 и маркер в треде: что идёт по сети, что кладётся в очередь, что отбрасывается. */
class VoiceProtocolTest {
    private fun message(audio: ByteArray = ByteArray(1_000) { it.toByte() }, id: String = "a1b2c3d4e5f6") = VoiceWireMessage(
        "PUBKEY+/=from", "Ярый: «Волк»", "Малстром", "PUBKEY+/=to", 1_700_000_000_000L, id, 12_345L,
        ByteArray(VoiceLimits.WAVEFORM_BARS) { (it * 3).toByte() }, audio,
    )

    @Test fun lineRoundTripsWithBinaryAudioAndFreeText() {
        val m = message()
        val back = VoiceProtocol.decode(VoiceProtocol.encode(m))!!
        assertEquals(m.fromCallsign, back.fromCallsign)
        assertEquals(m.fromFaction, back.fromFaction)
        assertEquals(m.fromPubKeyB64, back.fromPubKeyB64)
        assertEquals(m.toPubKeyB64, back.toPubKeyB64)
        assertEquals(m.timestamp, back.timestamp)
        assertEquals(m.id, back.id)
        assertEquals(m.durationMs, back.durationMs)
        assertArrayEquals(m.waveform, back.waveform)
        assertArrayEquals(m.audio, back.audio)
    }

    @Test fun maxSizeClipFitsInOneLine() {
        val line = VoiceProtocol.encode(message(audio = ByteArray(VoiceLimits.MAX_AUDIO_BYTES)))
        assertTrue("строка ${line.length} символов должна влезать в 256K с конвертом", line.length < 256 * 1024 - 1_000)
        assertNotNull(VoiceProtocol.decode(line))
    }

    @Test fun oversizeAudioIsRejected() {
        val line = VoiceProtocol.encode(message(audio = ByteArray(VoiceLimits.MAX_AUDIO_BYTES + 1)))
        assertNull(VoiceProtocol.decode(line))
    }

    @Test fun otherVersionAndGarbageAreRejected() {
        val line = VoiceProtocol.encode(message())
        assertNull(VoiceProtocol.decode(line.replaceFirst(":v1:", ":v2:")))
        assertNull(VoiceProtocol.decode(line.substringBeforeLast(':') + ":!!!не-base64"))
        assertNull(VoiceProtocol.decode("MB10CHAT:v1:x"))
        assertNull(VoiceProtocol.decode(""))
    }

    @Test fun unsafeIdsAreRejectedSoTheyCannotLeaveTheStorageFolder() {
        listOf("../../etc/passwd", "a/b/c/d/e/f/g/h", "short", "id with spaces!!", "x".repeat(65)).forEach {
            assertFalse(it, VoiceProtocol.isValidId(it))
        }
        assertTrue(VoiceProtocol.isValidId("0123456789abcdef-_ABC"))
        val line = VoiceProtocol.encode(message(id = "ok-id-123456"))
        assertNull(VoiceProtocol.decode(line.replace("ok-id-123456", "..%2f..%2fevil")))
    }

    @Test fun durationOutOfRangeIsRejected() {
        val line = VoiceProtocol.encode(message())
        assertNull(VoiceProtocol.decode(line.replace(":12345:", ":0:")))
        assertNull(VoiceProtocol.decode(line.replace(":12345:", ":${VoiceLimits.MAX_DURATION_MS + 10_000}:")))
    }

    @Test fun refLineKeepsEverythingExceptAudioAndIsNotAWireLine() {
        val m = message()
        val ref = VoiceProtocol.encodeRef(m)
        assertTrue(VoiceProtocol.isRef(ref))
        assertTrue("в очереди нет звука: ${ref.length}", ref.length < 600)
        assertNull("ссылка не принимается как строка провода", VoiceProtocol.decode(ref))
        val back = VoiceProtocol.decodeRef(ref)!!
        assertEquals(m.marker(), back.marker())
        assertEquals(m.timestamp, back.timestamp)
        assertEquals(0, back.audio.size)
    }

    @Test fun markerCarriesIdDurationAndWaveformForTheBubble() {
        val m = message()
        val parsed = VoiceMarker.parse(m.marker())!!
        assertEquals(m.id, parsed.id)
        assertEquals(m.durationMs, parsed.durationMs)
        assertArrayEquals(m.waveform, parsed.waveform)
        assertTrue(VoiceMarker.isVoice(m.marker()))
        assertNull(VoiceMarker.parse("обычный текст"))
        assertNull(VoiceMarker.parse("MB10VM:v1:../bad:1:AAAA"))
    }
}
