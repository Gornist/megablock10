package com.megablok10.app.voice

import com.megablok10.app.net.WireVersion
import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64
import java.util.Base64

/** Пределы голосового сообщения. Строка ≤ 256K символов (kit LineServer.DEFAULT_MAX_LINE_CHARS): 180 000 байт звука = 240 000 символов base64 + заголовок. */
object VoiceLimits {
    const val MAX_DURATION_MS = 60_000L
    const val MAX_AUDIO_BYTES = 180_000
    const val WAVEFORM_BARS = 64
    /** Целевой поток записи (бит/с): 60 с ≈ 150 КБ — с запасом до [MAX_AUDIO_BYTES]. */
    const val BITRATE = 20_000
    const val SAMPLE_RATE = 16_000
}

/** Голосовое сообщение на проводе: то же, что ляжет файлом ([audio]) и сообщением-маркером ([VoiceMarker]) у получателя. */
class VoiceWireMessage(
    val fromPubKeyB64: String,
    val fromCallsign: String,
    val fromFaction: String,
    val toPubKeyB64: String,
    val timestamp: Long,
    /** Имя файла и ключ дедупа вместе со временем и отправителем: только `[A-Za-z0-9_-]`, чтобы чужой id не вышел из папки хранилища. */
    val id: String,
    val durationMs: Long,
    /** [VoiceLimits.WAVEFORM_BARS] байт 0..255 — высота столбиков волны, посчитана при записи. */
    val waveform: ByteArray,
    val audio: ByteArray,
) {
    /** Текст сообщения в треде и в Room: маленький, звук лежит в файле. */
    fun marker(): String = VoiceMarker.encode(id, durationMs, waveform)

    fun withAudio(bytes: ByteArray) = VoiceWireMessage(fromPubKeyB64, fromCallsign, fromFaction, toPubKeyB64, timestamp, id, durationMs, waveform, bytes)
}

/**
 * Построчный протокол голосового (app/docs/voice-messages.md): как чат, но со звуком в той же строке — `MB10VOICE:v1:от:позывной:фракция:кому:время:id:мс:волна:звук`.
 * Свободный текст и двоичные поля — base64 (без `:`). Строка ссылки [encodeRef] (`MB10VREF`) без звука живёт только в очереди исходящих на самом телефоне:
 * звук подтягивается из файла при отправке, а не хранится в Room вторым экземпляром.
 */
object VoiceProtocol {
    private const val MAGIC = "MB10VOICE"
    private const val REF_MAGIC = "MB10VREF"
    private val ID = Regex("[A-Za-z0-9_-]{8,64}")

    fun isValidId(id: String): Boolean = ID.matches(id)

    fun encode(m: VoiceWireMessage): String = header(MAGIC, "v${WireVersion.VOICE}", m) + ":" + Base64.getEncoder().encodeToString(m.audio)

    /** Строка для очереди исходящих: всё, кроме звука. */
    fun encodeRef(m: VoiceWireMessage): String = header(REF_MAGIC, "v${WireVersion.VOICE}", m)

    fun decode(raw: String): VoiceWireMessage? {
        val parts = raw.split(":")
        if (parts.size != 11 || !WireVersion.matches(parts, MAGIC)) return null
        return build(parts, audio = decodeBytes(parts[10], VoiceLimits.MAX_AUDIO_BYTES) ?: return null)
    }

    /** Разбор строки ссылки; звук в сообщении пуст. */
    fun decodeRef(raw: String): VoiceWireMessage? {
        val parts = raw.split(":")
        if (parts.size != 10 || parts[0] != REF_MAGIC || parts[1] != "v${WireVersion.VOICE}") return null
        return build(parts, audio = ByteArray(0))
    }

    fun isRef(line: String): Boolean = line.startsWith("$REF_MAGIC:")

    private fun header(magic: String, version: String, m: VoiceWireMessage): String = listOf(
        magic, version, m.fromPubKeyB64, b64(m.fromCallsign), b64(m.fromFaction), m.toPubKeyB64,
        m.timestamp.toString(), m.id, m.durationMs.toString(), Base64.getEncoder().encodeToString(m.waveform),
    ).joinToString(":")

    private fun build(parts: List<String>, audio: ByteArray): VoiceWireMessage? = try {
        val id = parts[7]
        val duration = parts[8].toLongOrNull()?.takeIf { it in 1..VoiceLimits.MAX_DURATION_MS + DURATION_SLACK_MS }
        val waveform = decodeBytes(parts[9], VoiceLimits.WAVEFORM_BARS)
        val timestamp = parts[6].toLongOrNull()
        if (!isValidId(id)) null
        else if (duration == null || waveform == null || timestamp == null) null
        else VoiceWireMessage(parts[2], unb64(parts[3]), unb64(parts[4]), parts[5], timestamp, id, duration, waveform, audio)
    } catch (e: IllegalArgumentException) {
        null
    }

    /** null — слишком длинно или не base64; пустое поле — пустой массив. */
    private fun decodeBytes(field: String, maxBytes: Int): ByteArray? {
        if (field.length > maxBytes / 3 * 4 + 4) return null
        val bytes = try { Base64.getDecoder().decode(field) } catch (e: IllegalArgumentException) { return null }
        return bytes.takeIf { it.size <= maxBytes }
    }

    /** Запись останавливается на пределе с небольшим запасом на округление таймера. */
    private const val DURATION_SLACK_MS = 2_000L
}

/**
 * Сообщение-маркер в треде: `MB10VM:v1:id:мс:волна`. Звук — файл [VoiceStore]; маркер вместе со временем и отправителем даёт дедуп (`countSame`),
 * а экрану — всё для рисунка пузыря (длительность, волна) без чтения файла.
 */
object VoiceMarker {
    private const val MAGIC = "MB10VM"

    data class Parsed(val id: String, val durationMs: Long, val waveform: ByteArray)

    fun encode(id: String, durationMs: Long, waveform: ByteArray): String =
        listOf(MAGIC, "v1", id, durationMs.toString(), Base64.getEncoder().encodeToString(waveform)).joinToString(":")

    fun parse(body: String): Parsed? {
        if (!body.startsWith("$MAGIC:")) return null
        val parts = body.split(":")
        if (parts.size != 5 || parts[1] != "v1" || !VoiceProtocol.isValidId(parts[2])) return null
        val duration = parts[3].toLongOrNull() ?: return null
        val waveform = try { Base64.getDecoder().decode(parts[4]) } catch (e: IllegalArgumentException) { return null }
        return Parsed(parts[2], duration, waveform)
    }

    fun isVoice(body: String): Boolean = body.startsWith("$MAGIC:")
}
