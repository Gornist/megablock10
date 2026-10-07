package com.megablok10.app.voice

import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.chat.statusOf
import com.megablok10.app.data.ChatMessageDao
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val TAG = "VoiceMessenger"

/** Следующее непрослушанное входящее голосовое от [peer] после [after] — для автопроигрывания (то, что получает [VoicePlayer.nextUnlistened]). */
suspend fun ChatMessageDao.nextUnlistenedTrack(me: String, peer: String, after: Long): VoiceTrack? = nextUnlistenedVoice(me, peer, after)?.voiceTrack(me)

/** Голосовое из строки ленты; null — это не голосовое. [me] — мой ключ: чужое входящее, своё исходящее. */
fun ChatMessageEntity.voiceTrack(me: String): VoiceTrack? = VoiceMarker.parse(body)?.let {
    val incoming = fromPubKeyB64 != me
    VoiceTrack(id, it.id, it.durationMs, peerKey = if (incoming) fromPubKeyB64 else toPubKeyB64, incoming = incoming, timestamp = timestamp)
}

/**
 * Голосовые сообщения личного чата (app/docs/voice-messages.md): отправка тем же путём, что текст, — прямо адресату, не ушло — в очередь исходящих.
 * Отличия от текста: звук хранится файлом ([VoiceStore]), в Room лежит маркер ([VoiceMarker]); в очередь кладётся строка-ссылка без звука
 * ([VoiceProtocol.encodeRef]), звук подтягивается при отправке ([expand]); приём сохраняет файл ДО записи в Room и до ответа «доставлено» (D2).
 */
class VoiceMessenger(
    private val dao: ChatMessageDao,
    private val outbox: OutboxStore,
    private val peers: PeerDirectory,
    private val store: VoiceStore,
) {
    /**
     * Отправить записанное [audio] собеседнику [peerPubKeyB64]. null — запись не принята (пустая, длиннее предела, чужой id); иначе исход отправки
     * (как у текста: DELIVERED / UNKNOWN «могло дойти» / NOT_REACHED, два последних — в очереди). [peer] — живой адрес или null, если адресата не видно.
     */
    suspend fun send(
        identity: Identity,
        peerPubKeyB64: String,
        peer: OnlinePlayer?,
        id: String,
        durationMs: Long,
        waveform: ByteArray,
        audio: ByteArray,
    ): SendOutcome? {
        if (durationMs !in 1..VoiceLimits.MAX_DURATION_MS || waveform.size > VoiceLimits.WAVEFORM_BARS) return null
        if (!store.write(id, audio)) return null
        val wire = VoiceWireMessage(identity.publicKeyB64, identity.callsign, identity.faction, peerPubKeyB64, System.currentTimeMillis(), id, durationMs, waveform, audio)
        val rowId = persist(wire)
        val outcome = if (peer == null) SendOutcome.NOT_REACHED else withContext(Dispatchers.IO) { peers.send(peerPubKeyB64, VoiceProtocol.encode(wire)) }
        if (outcome != SendOutcome.DELIVERED) outbox.enqueueLine(peerPubKeyB64, VoiceProtocol.encodeRef(wire))
        Mb10Log.event(
            TAG, "voice.send", "to" to Mb10Log.short(peerPubKeyB64), "peerVisible" to (peer != null), "outcome" to outcome.name,
            "queued" to (outcome != SendOutcome.DELIVERED), "bytes" to audio.size, "ms" to durationMs,
        )
        dao.raiseStatus(rowId, statusOf(outcome))
        return outcome
    }

    /** Принять с провода: файл — потом строка в Room; false — повтор уже принятого. Бросает при сбое записи файла: подтверждения «доставлено» не будет, отправитель повторит. */
    suspend fun receive(message: VoiceWireMessage): Boolean {
        check(store.write(message.id, message.audio)) { "voice file not saved: ${message.id}" }
        val marker = message.marker()
        val fresh = dao.countSame(message.fromPubKeyB64, message.timestamp, ChatMessageType.DM.name, marker) == 0
        if (fresh) persist(message)
        Mb10Log.event(
            TAG, "voice.recv", "from" to Mb10Log.short(message.fromPubKeyB64), "bytes" to message.audio.size, "ms" to message.durationMs,
            "duplicate" to !fresh, "ageMs" to (System.currentTimeMillis() - message.timestamp),
        )
        return fresh
    }

    private suspend fun persist(m: VoiceWireMessage): Long = dao.insert(
        ChatMessageEntity(
            type = ChatMessageType.DM.name, fromPubKeyB64 = m.fromPubKeyB64, fromCallsign = m.fromCallsign, faction = m.fromFaction,
            toPubKeyB64 = m.toPubKeyB64, body = m.marker(), timestamp = m.timestamp,
        )
    )

    companion object {
        /**
         * Строка очереди → строка для отправки: ссылка дополняется звуком из файла; всё остальное — как есть. null — файл пропал: слать нечего,
         * запись очереди снимается (OutboxStore), статус сообщения остаётся «не ушло».
         */
        fun expand(line: String, store: VoiceStore): String? {
            if (!VoiceProtocol.isRef(line)) return line
            val ref = VoiceProtocol.decodeRef(line) ?: return null
            val audio = store.read(ref.id) ?: return null
            return VoiceProtocol.encode(ref.withAudio(audio))
        }
    }
}
