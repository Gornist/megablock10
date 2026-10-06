package com.megablok10.app.headset

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Частота звука между телефоном и очками (моно PCM 16 бит): так отдаёт микрофон Godot на Android. */
const val HEADSET_VOICE_RATE = 44_100

/** Кусок звука в кадре: 20 мс при [HEADSET_VOICE_RATE]. */
const val HEADSET_VOICE_CHUNK = 882

/**
 * Бинарный кадр голоса по тому же WebSocket, что и JSON-кадры: `[тип 1 байт][seq uint32 LE][PCM int16 LE моно]`. Тип 1 — микрофон очков →
 * телефон, тип 2 — звук собеседника телефон → очки. Формат — docs/netrun-phone-link.md (срез 3).
 */
class VoiceFrame(val type: Int, val seq: Long, val pcm: ShortArray) {
    override fun equals(other: Any?) = other is VoiceFrame && type == other.type && seq == other.seq && pcm.contentEquals(other.pcm)
    override fun hashCode() = (type * 31 + seq.hashCode()) * 31 + pcm.contentHashCode()
    override fun toString() = "VoiceFrame(type=$type, seq=$seq, samples=${pcm.size})"
}

object HeadsetVoiceCodec {
    const val TYPE_MIC = 1
    const val TYPE_PLAYBACK = 2
    private const val HEADER = 5
    private const val MAX_PAYLOAD = 4096
    private const val BYTES_PER_SAMPLE = 2

    fun encode(type: Int, seq: Long, pcm: ShortArray): ByteArray {
        val buf = ByteBuffer.allocate(HEADER + pcm.size * BYTES_PER_SAMPLE).order(ByteOrder.LITTLE_ENDIAN)
        buf.put(type.toByte()).putInt(seq.toInt())
        for (s in pcm) buf.putShort(s)
        return buf.array()
    }

    /** Терпимый разбор: слишком короткий, нечётной длины, длиннее [MAX_PAYLOAD] или неизвестного типа кадр — `null`. */
    fun decode(bytes: ByteArray): VoiceFrame? {
        val payload = bytes.size - HEADER
        if (payload < 0 || payload > MAX_PAYLOAD || payload % BYTES_PER_SAMPLE != 0) return null
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val type = buf.get().toInt()
        if (type != TYPE_MIC && type != TYPE_PLAYBACK) return null
        val seq = buf.getInt().toLong() and SEQ_MASK
        val pcm = ShortArray(payload / BYTES_PER_SAMPLE) { buf.getShort() }
        return VoiceFrame(type, seq, pcm)
    }

    private const val SEQ_MASK = 0xFFFF_FFFFL
}
