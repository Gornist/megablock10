package com.megablok10.app.voice

import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.data.ChatMessageDao
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.WireVersion
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.net.SendOutcome
import com.megablok10.app.chat.ReadReceiptSetting
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val TAG = "VoiceReceipts"

/** «Я прослушал твоё голосовое [clipId]»: [listener] — кто прослушал, [author] — чьё голосовое. */
data class VoiceListened(val listener: String, val author: String, val clipId: String)

/**
 * Отчёт о прослушивании на проводе: `MB10LISTEN:v1:<слушатель>:<автор>:<id голосового>`. Отдельный мини-протокол рядом с `MB10READ` (формат чата и его версия не меняются);
 * повтор и опоздание безопасны (статус «прослушано» только растёт). Доходит как любая строка: напрямую, не вышло — через очередь исходящих.
 */
object VoiceListenProtocol {
    private const val MAGIC = "MB10LISTEN"

    fun encode(r: VoiceListened): String = "$MAGIC:v${WireVersion.VOICE_LISTENED}:${r.listener}:${r.author}:${r.clipId}"

    fun decode(raw: String): VoiceListened? {
        val parts = raw.split(":")
        if (parts.size != 5 || !WireVersion.matches(parts, MAGIC)) return null
        if (parts[2].isEmpty() || parts[3].isEmpty() || !VoiceProtocol.isValidId(parts[4])) return null
        return VoiceListened(parts[2], parts[3], parts[4])
    }
}

/**
 * Синие ✓✓ у голосового: слушатель, впервые запустивший чужое голосовое, шлёт автору отчёт ([onPlayed]); автор, получив его ([onReceived]), поднимает статус своего
 * сообщения до [MessageStatus.LISTENED]. Тот же переключатель «Отчёты о прочтении», что у MB10READ: выключен — свои отчёты не уходят (чужие по-прежнему принимаются, но не показываются).
 */
class VoiceReceipts(
    private val dao: ChatMessageDao,
    private val peers: PeerDirectory,
    private val outbox: OutboxStore,
    private val setting: ReadReceiptSetting,
    private val me: () -> String?,
) {
    /** Строка [rowId] проиграна: помечаем прослушанной у себя; если это было впервые — отчёт автору. */
    suspend fun onPlayed(rowId: Long) {
        if (dao.markListened(rowId) != 1) return // уже была прослушана: отчёт уходил
        val myKey = me() ?: return
        val row = dao.byId(rowId) ?: return
        val clip = VoiceMarker.parse(row.body)?.id
        // своё голосовое себе не отчитывается; выключенные отчёты: точка гаснет, автору ничего не уходит
        if (clip != null && row.fromPubKeyB64 != myKey && setting.enabled.value) report(myKey, row.fromPubKeyB64, clip)
    }

    private suspend fun report(myKey: String, author: String, clip: String) {
        val line = VoiceListenProtocol.encode(VoiceListened(myKey, author, clip))
        val outcome = withContext(Dispatchers.IO) { peers.send(author, line) }
        Mb10Log.event(TAG, "voice.listen_sent", "to" to Mb10Log.short(author), "clip" to clip.take(8), "outcome" to outcome.name)
        if (outcome != SendOutcome.DELIVERED) outbox.enqueueLine(author, line)
    }

    /** Чужой отчёт о моём голосовом. */
    suspend fun onReceived(me: String, receipt: VoiceListened) {
        if (receipt.author != me) return
        val marked = dao.markVoiceListenedBy(me, receipt.listener, receipt.clipId)
        Mb10Log.event(TAG, "voice.listen_recv", "from" to Mb10Log.short(receipt.listener), "clip" to receipt.clipId.take(8), "marked" to marked)
    }
}
