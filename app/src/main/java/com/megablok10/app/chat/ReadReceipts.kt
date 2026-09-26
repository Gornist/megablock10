package com.megablok10.app.chat

import android.content.SharedPreferences
import com.megablok10.app.data.ChatMessageDao
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.WireVersion
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.net.SendOutcome
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

private const val TAG = "ReadReceipts"

/** «Прочитал все твои личные сообщения до [upTo]» (время отправителя): [reader] — кто прочитал, [author] — чьи сообщения. */
data class ReadReceipt(val reader: String, val author: String, val upTo: Long)

/**
 * Отчёт о прочтении на проводе (docs/refactor-plan.md, D4): `MB10READ:v1:<reader>:<author>:<upTo>`. Отдельный протокол, а не тип
 * сообщения чата: формат чата и его версия не меняются. Водяной знак по времени, а не по id сообщения: отчёт «до T» закрывает
 * все сообщения до T разом, повтор и опоздание безопасны (статус растёт только вверх).
 */
object ReadReceiptProtocol {
    const val MAGIC = "MB10READ"

    fun encode(r: ReadReceipt): String = "$MAGIC:v${WireVersion.READ}:${r.reader}:${r.author}:${r.upTo}"

    fun decode(raw: String): ReadReceipt? {
        val parts = raw.split(":")
        if (parts.size != 5 || !WireVersion.matches(parts, MAGIC)) return null
        val upTo = parts[4].toLongOrNull() ?: return null
        if (parts[2].isEmpty() || parts[3].isEmpty()) return null
        return ReadReceipt(parts[2], parts[3], upTo)
    }
}

/**
 * Переключатель «Отчёты о прочтении», как в мессенджерах: выключен — свои отчёты не уходят и чужое «прочитано» не показывается
 * (отметка остаётся «доставлено»). По умолчанию включён. Хранится в своём файле настроек (`chat_prefs`).
 */
class ReadReceiptSetting(private val prefs: SharedPreferences) {
    private val _enabled = MutableStateFlow(prefs.getBoolean(KEY, true))
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun set(on: Boolean) {
        prefs.edit().putBoolean(KEY, on).apply() // не подтверждение для сети — достаточно apply()
        _enabled.value = on
        Mb10Log.event(TAG, "read_receipts.setting", "enabled" to on)
    }

    companion object {
        const val PREFS = "chat_prefs"
        private const val KEY = "read_receipts"
    }
}

/**
 * Отчёты о прочтении личных сообщений: отправить автору, когда игрок видит тред ([onThreadShown]), и принять от собеседника
 * ([onReceived] — «мои сообщения ему прочитаны до T»). Не дошло — в очередь исходящих: уйдёт, когда автор появится.
 */
class ReadReceipts(
    private val dao: ChatMessageDao,
    private val peers: PeerDirectory,
    private val outbox: OutboxStore,
    private val setting: ReadReceiptSetting,
) {
    /** Последний отправленный водяной знак на собеседника — чтобы не слать тот же отчёт на каждое обновление ленты. */
    private val sent = ConcurrentHashMap<String, Long>()

    /** Что стало с отчётом — для журнала и стенда e2e. */
    enum class Result { OFF, NOTHING_NEW, SENT, QUEUED }

    suspend fun onThreadShown(me: String, peerKey: String, messages: List<ChatMessageEntity>): Result {
        if (!setting.enabled.value) return Result.OFF
        val upTo = messages.filter { it.type == ChatMessageType.DM.name && it.fromPubKeyB64 == peerKey }.maxOfOrNull { it.timestamp }
            ?: return Result.NOTHING_NEW
        if ((sent[peerKey] ?: Long.MIN_VALUE) >= upTo) return Result.NOTHING_NEW
        sent[peerKey] = upTo
        val line = ReadReceiptProtocol.encode(ReadReceipt(me, peerKey, upTo))
        val outcome = withContext(Dispatchers.IO) { peers.send(peerKey, line) }
        Mb10Log.event(TAG, "read.sent", "to" to Mb10Log.short(peerKey), "upTo" to upTo, "outcome" to outcome.name)
        if (outcome == SendOutcome.DELIVERED) return Result.SENT
        outbox.enqueueLine(peerKey, line)
        return Result.QUEUED
    }

    /** Чужой отчёт о моих сообщениях: помечаем прочитанными (показ зависит от переключателя, хранение — нет). */
    suspend fun onReceived(me: String, receipt: ReadReceipt) {
        if (receipt.author != me) return
        val marked = dao.markReadUpTo(me, receipt.reader, receipt.upTo)
        Mb10Log.event(TAG, "read.recv", "from" to Mb10Log.short(receipt.reader), "upTo" to receipt.upTo, "marked" to marked)
    }
}
