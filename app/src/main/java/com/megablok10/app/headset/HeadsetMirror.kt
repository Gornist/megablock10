package com.megablok10.app.headset

import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.qr.Mb10QrCodec
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Откуда зеркало берёт переписку и куда отправляет ответы. Реализация — поверх ChatStore/Room (ChatStoreHeadsetPort); в тестах — фейк. */
interface HeadsetChatPort {
    /** Любое изменение переписки (личной или фракционной) — повод пересчитать кадры. Первое значение приходит сразу. */
    fun changes(me: Identity): Flow<Unit>

    /** Ключи собеседников, с которыми есть личная переписка. */
    suspend fun directPeers(me: String): List<String>

    /** Последние [limit] сообщений личного диалога, старые первыми. Служебные карточки в них есть — фильтрует зеркало. */
    suspend fun recentDirect(me: String, peerPubKey: String, limit: Int): List<ChatMessageEntity>

    suspend fun recentFaction(faction: String, limit: Int): List<ChatMessageEntity>

    /** Позывной собеседника по ключу (контакты, видимые игроки); null — не знаем. */
    suspend fun peerCallsign(pubKey: String): String?

    suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, text: String): Boolean

    suspend fun sendFaction(identity: Identity, text: String)

    /** Контакты игрока (отсканированные QR других игроков) — кому можно позвонить из очков. Первое значение приходит сразу. */
    fun contacts(): Flow<List<HeadsetContact>>
}

/** До какого момента диалог прочитан (в очках) — отдельно от общего счётчика вкладки «Чат». Время — миллисекунды сообщения. */
interface HeadsetReadState {
    fun lastRead(thread: String): Long?
    fun setLastRead(thread: String, upToMs: Long)
}

/**
 * Телефон как источник данных для очков: превращает переписку в кадры [HeadsetOut] и исполняет команды [HeadsetCommand]. Сеть и
 * WebSocket — снаружи ([HeadsetRuntime]): сюда приходят уже разобранные команды, а кадры уходят через `send`.
 *
 * Порядок на одном соединении: `hello` → ждём `hello_ack` (до него команды игнорируем) → следят за перепиской: при каждом изменении
 * очкам уходит разница (`threads` при изменении списка, `message` на каждое новое или изменившееся сообщение). `resync` очков — полная
 * замена: `threads` и `messages` по каждому диалогу.
 *
 * Служебные карточки в личных диалогах (переводы, предметы, чеки, сигналы СБ — всё, что разбирает [Mb10QrCodec]) очкам не показываются.
 */
class HeadsetMirror(
    private val chat: HeadsetChatPort,
    private val me: () -> Identity?,
    private val readState: HeadsetReadState,
    private val onReady: (Boolean) -> Unit = {},
    /** Звонки (срез 2): без него зеркало показывает только переписку. */
    private val callBridge: HeadsetCallBridge? = null,
    /** Голос звонка в очках (срез 3): без него звук звонка остаётся на телефоне. */
    private val voiceBridge: HeadsetVoiceBridge? = null,
) {
    private class Sent {
        var threads: List<HeadsetThread> = emptyList()
        val messages = HashMap<String, HashMap<String, String>>() // диалог → id → статус, который уже отправили
    }

    /**
     * Обслуживает одно соединение, пока оно живо (возвращается, когда [commands] закрыт, и выбрасывает [CancellationException] при отмене).
     * [send] отдаёт кадр очкам; false — сокет кадр не принял (его закрывает [HeadsetRuntime]). [sendBinary] — то же для бинарных кадров голоса.
     */
    suspend fun serve(send: (HeadsetOut) -> Boolean, commands: ReceiveChannel<HeadsetCommand>, sendBinary: (ByteArray) -> Boolean = { false }) {
        val identity = me() ?: return
        coroutineScope {
            val sent = Sent()
            val lock = Mutex()
            var observer: Job? = null
            suspend fun push(full: Boolean) = lock.withLock { pushLocked(identity, send, sent, full) }

            if (!send(HeadsetOut.Hello(identity.callsign))) return@coroutineScope
            try {
                for (cmd in commands) {
                    when {
                        cmd is HeadsetCommand.HelloAck -> if (observer == null) {
                            Mb10Log.event(TAG, "headset.ready", "v" to cmd.v)
                            onReady(true)
                            observer = launch {
                                callBridge?.observe(this, send)
                                voiceBridge?.observe(this, send, sendBinary)
                                launch { chat.contacts().distinctUntilChanged().collect { send(HeadsetOut.Contacts(it)) } }
                                var first = true
                                chat.changes(identity).conflate().collect { push(full = first).also { first = false } }
                            }
                        }
                        observer == null -> Unit // до hello_ack очки не слушают
                        else -> launch { runCommand(identity, cmd, send, sent, lock) }
                    }
                }
            } finally {
                observer?.cancel()
                voiceBridge?.stop()
                onReady(false)
            }
        }
    }

    /** Бинарный кадр от очков (микрофон) — прямо из сетевого потока, без очереди команд: кадров 50 в секунду. */
    fun onBinary(bytes: ByteArray) {
        voiceBridge?.onBinary(bytes)
    }

    /** Одна команда очков в своей корутине: долгая отправка (сеть) не задерживает остальные. Сбой команды в журнал, соединение не роняет. */
    private suspend fun runCommand(identity: Identity, cmd: HeadsetCommand, send: (HeadsetOut) -> Boolean, sent: Sent, lock: Mutex) {
        try {
            handle(identity, cmd, send, sent, lock)
        } catch (e: CancellationException) {
            throw e
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            Mb10Log.w(TAG, "команда очков ${cmd::class.simpleName} не выполнена: ${e.message}", e)
        }
    }

    private suspend fun handle(identity: Identity, cmd: HeadsetCommand, send: (HeadsetOut) -> Boolean, sent: Sent, lock: Mutex) {
        when (cmd) {
            is HeadsetCommand.Resync -> {
                lock.withLock { pushLocked(identity, send, sent, full = true) }
                send(HeadsetOut.Contacts(chat.contacts().first()))
                callBridge?.snapshot(send)
            }
            is HeadsetCommand.MarkRead -> {
                val latest = loadThread(identity, cmd.thread).lastOrNull()?.timestamp ?: return
                readState.setLastRead(cmd.thread, latest)
                lock.withLock { pushLocked(identity, send, sent, full = false) }
            }
            is HeadsetCommand.SendText -> {
                val text = HEADSET_PRESETS[cmd.preset]
                if (text == null) {
                    Mb10Log.warnEvent(TAG, "headset.unknown_preset", "preset" to cmd.preset)
                    return
                }
                if (cmd.thread == HEADSET_FACTION_THREAD) chat.sendFaction(identity, text) else chat.sendDirect(identity, cmd.thread, text)
            }
            is HeadsetCommand.VoiceReady -> voiceBridge?.handle(cmd)
            else -> callBridge?.handle(identity, cmd) // звонки; hello_ack обработан выше
        }
    }

    private suspend fun loadThread(identity: Identity, thread: String): List<ChatMessageEntity> =
        if (thread == HEADSET_FACTION_THREAD) {
            chat.recentFaction(identity.faction, FACTION_DEPTH).filterNot(::isService)
        } else {
            chat.recentDirect(identity.publicKeyB64, thread, DIRECT_DEPTH).filterNot(::isService)
        }

    private suspend fun pushLocked(identity: Identity, send: (HeadsetOut) -> Boolean, sent: Sent, full: Boolean) {
        val loaded = LinkedHashMap<String, List<ChatMessageEntity>>()
        loaded[HEADSET_FACTION_THREAD] = loadThread(identity, HEADSET_FACTION_THREAD)
        for (peer in chat.directPeers(identity.publicKeyB64)) {
            val messages = loadThread(identity, peer)
            if (messages.isNotEmpty()) loaded[peer] = messages
        }
        val threads = loaded.map { (id, messages) -> threadOf(identity, id, messages) }
        if (full || threads != sent.threads) {
            sent.threads = threads
            send(HeadsetOut.Threads(threads))
        }
        for ((id, messages) in loaded) {
            val items = messages.map { messageOf(identity, id, it) }
            val known = sent.messages.getOrPut(id) { HashMap() }
            if (full) {
                known.clear()
                items.forEach { known[it.id] = it.status }
                send(HeadsetOut.Messages(id, items))
            } else {
                for (item in items) {
                    if (known[item.id] == item.status) continue
                    known[item.id] = item.status
                    send(HeadsetOut.Message(item))
                }
            }
        }
    }

    private suspend fun threadOf(identity: Identity, id: String, messages: List<ChatMessageEntity>): HeadsetThread {
        val last = messages.lastOrNull()
        val isFaction = id == HEADSET_FACTION_THREAD
        val title = when {
            isFaction -> identity.faction
            else -> chat.peerCallsign(id) ?: messages.lastOrNull { it.fromPubKeyB64 == id }?.fromCallsign ?: Mb10Log.short(id)
        }
        // Первый раз видим диалог — считаем прочитанным всё, что в нём уже есть, иначе очки при первом подключении получили бы всю историю как «новое».
        val readUpTo = readState.lastRead(id) ?: (last?.timestamp ?: 0L).also { readState.setLastRead(id, it) }
        return HeadsetThread(
            id = id,
            kind = if (isFaction) HeadsetThread.KIND_FACTION else HeadsetThread.KIND_DM,
            title = title,
            lastText = last?.body.orEmpty(),
            lastTs = (last?.timestamp ?: 0L) / MS_PER_S,
            unread = messages.count { it.fromPubKeyB64 != identity.publicKeyB64 && it.timestamp > readUpTo },
        )
    }

    private fun messageOf(identity: Identity, thread: String, m: ChatMessageEntity): HeadsetMessage {
        val mine = m.fromPubKeyB64 == identity.publicKeyB64
        return HeadsetMessage(
            id = m.id.toString(),
            thread = thread,
            mine = mine,
            text = m.body,
            ts = m.timestamp / MS_PER_S,
            status = statusOf(mine, m.status),
            from = if (thread == HEADSET_FACTION_THREAD) m.fromCallsign else "",
        )
    }

    private fun isService(m: ChatMessageEntity): Boolean = Mb10QrCodec.decode(m.body) != null

    companion object {
        private const val TAG = "Headset"
        private const val MS_PER_S = 1000L
        /** Глубина истории по resync: личный диалог — 20 сообщений, фракционный чат — 40 (два экрана прокрутки в деке). */
        const val DIRECT_DEPTH = 20
        const val FACTION_DEPTH = 40

        /**
         * Статус сообщения для очков: прочитано и доставлено → `delivered`; всё остальное у своих (в очереди, ушло без подтверждения, фракционное) →
         * `sent`; чужие — `delivered`. `failed` приложение сейчас не производит (в очереди сообщение живёт до 12 часов), но очки его понимают.
         */
        fun statusOf(mine: Boolean, status: Int): String = when {
            !mine -> HeadsetMessage.DELIVERED
            status >= MessageStatus.DELIVERED -> HeadsetMessage.DELIVERED
            else -> HeadsetMessage.SENT
        }
    }
}
