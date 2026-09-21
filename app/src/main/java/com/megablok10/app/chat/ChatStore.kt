package com.megablok10.app.chat

import android.content.Context
import com.megablok10.app.breach.SecAlertStore
import com.megablok10.app.breach.SlotClaimStore
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.identity.Identity
import com.megablok10.app.net.IncompatibleVersionReporter
import com.megablok10.app.net.SendOutcome
import com.megablok10.app.call.CallManager
import com.megablok10.app.log.DeviceDiagnostics
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.presence.WifiBinder
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.sound.SoundPlayer
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Запускается один раз на время жизни приложения (из AppRoot, а не из
 * ChatScreen — вкладки Compose размонтируются при переключении, а входящие
 * сообщения должны приниматься и сохраняться, даже когда игрок на другой
 * вкладке). Держит сервер на приём + presence на обнаружение и знает, как
 * разослать/сохранить исходящее.
 */
private const val TAG = "ChatStore"

object ChatStore {
    private var server: ChatServer? = null

    /** Порт, на котором сейчас слушает приложение (-1 — не запущен). Нужен стенду e2e, чтобы связать эмуляторы после перезапуска. */
    val listeningPort: Int get() = server?.port ?: -1
    private var scope: CoroutineScope? = null
    private var startedForKey: String? = null
    private val versionReporter = IncompatibleVersionReporter { com.megablok10.app.ui.theme.AppSnack.show(it) }

    /**
     * Сама функция синхронная (её удобно звать из LaunchedEffect на главном
     * потоке), но всё, что реально блокирует — bind сокета, регистрация
     * NSD — уходит в appScope на Dispatchers.IO, а не выполняется тут же.
     */
    fun start(context: Context, identity: Identity) {
        if (startedForKey == identity.publicKeyB64) return
        stop()
        startedForKey = identity.publicKeyB64
        Mb10Log.event(TAG, "chat.start", "me" to Mb10Log.short(identity.publicKeyB64), "callsign" to identity.callsign, "faction" to identity.faction)

        val appContext = context.applicationContext
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope = appScope

        SoundPlayer.preload(appContext)
        // Трафик приложения — только по Wi-Fi игровой сети; при смене сети NSD перерегистрируется (docs/network-spec.md, §7).
        WifiBinder.start(appContext) { PresenceService.refresh() }

        appScope.launch {
            val srv = ChatServer(
                onMessage = { msg ->
                    appScope.launch {
                        // Повторная доставка того же сообщения (отправитель не увидел подтверждения и переслал из очереди) не дублируется.
                        val fresh = persistIfNew(appContext, msg)
                        Mb10Log.event(TAG, "chat.recv", "type" to msg.type.name, "from" to Mb10Log.short(msg.fromPubKeyB64), "chars" to msg.body.length, "duplicate" to !fresh, "ageMs" to (System.currentTimeMillis() - msg.timestamp))
                        if (!fresh) return@launch
                        confirmIfReceipt(appContext, msg)
                    }
                    // Звук — только для реально пришедших по сети сообщений (этот колбэк
                    // и есть приём с провода), свои же исходящие persist() не должны пищать.
                    SoundPlayer.playMessageReceived(appContext)
                },
                onCallSignal = { signal -> CallManager.onSignalReceived(appContext, identity, signal) },
                onSlotClaim = { claim -> appScope.launch { SlotClaimStore.receive(appContext, claim) } },
                onIncompatible = { line -> versionReporter.report(line) }
            )
            srv.start(appScope)
            server = srv
            PresenceService.start(appContext, identity, srv.port)
            SecAlertStore.start(appContext, appScope)
            DeviceDiagnostics.startSnapshots(appContext, appScope)
        }

        // Очередь исходящих: досылаем, как только адресат снова виден, и по таймеру (для повторов с паузой).
        appScope.launch { PresenceService.peers.collect { OutboxStore.flush(appContext) } }
        appScope.launch { while (true) { delay(5_000); OutboxStore.flush(appContext) } }
    }

    fun stop() {
        Mb10Log.event(TAG, "chat.stop")
        server?.stop()
        PresenceService.stop()
        WifiBinder.stop()
        scope?.cancel()
        server = null
        scope = null
        startedForKey = null
    }

    fun observeFaction(context: Context, faction: String): Flow<List<ChatMessageEntity>> =
        Mb10Database.get(context).chatMessageDao().observeFaction(faction)

    fun observeDirect(context: Context, myPubKey: String, peerPubKey: String): Flow<List<ChatMessageEntity>> =
        Mb10Database.get(context).chatMessageDao().observeDirect(myPubKey, peerPubKey)

    /** Последнее сообщение с каждым собеседником — для инбокса. */
    fun observeRecentDirectThreads(context: Context, myPubKey: String): Flow<List<ChatMessageEntity>> =
        Mb10Database.get(context).chatMessageDao().observeRecentDirectThreads(myPubKey)

    /** Сохраняет свою копию сразу и рассылает всем сейчас видимым игрокам своей фракции — доставка best-effort, без подтверждений и ретраев. */
    suspend fun sendFaction(context: Context, identity: Identity, body: String) {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.FACTION, identity.publicKeyB64, identity.callsign, identity.faction, "", timestamp, body)
        persist(context, wire)
        val recipients = PresenceService.peers.value.filter { it.faction == identity.faction }
        Mb10Log.event(TAG, "chat.send_faction", "recipients" to recipients.size, "chars" to body.length)
        withContext(Dispatchers.IO) {
            recipients.forEach { peer -> if (!ChatClient.send(peer.host, peer.port, wire)) OutboxStore.enqueue(context, peer.pubKeyB64, wire) }
        }
    }

    /**
     * peerPubKeyB64 — личность адресата (известна всегда, из контактов, вне
     * зависимости от того, онлайн он сейчас или нет) — именно она идёт в
     * запись треда, иначе observeDirect потом не найдёт своё же сообщение по
     * фильтру "от меня к нему". peer — живой адрес для реальной отправки
     * (null, если сейчас не в сети): без него есть кому, но некуда стучаться,
     * сообщение всё равно останется в треде локально.
     */
    suspend fun sendDirect(context: Context, identity: Identity, peerPubKeyB64: String, peer: PeerInfo?, body: String): Boolean =
        sendDirectOutcome(context, identity, peerPubKeyB64, peer, body) == SendOutcome.DELIVERED

    /** Как [sendDirect], но с различением «точно не ушло» и «могло уйти» — нужно деньгам и предметам (TransactionStore.deliverOutgoing). */
    suspend fun sendDirectOutcome(context: Context, identity: Identity, peerPubKeyB64: String, peer: PeerInfo?, body: String): SendOutcome {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.DM, identity.publicKeyB64, identity.callsign, identity.faction, peerPubKeyB64, timestamp, body)
        persist(context, wire)
        val outcome = if (peer == null) SendOutcome.NOT_REACHED else withContext(Dispatchers.IO) { ChatClient.sendOutcome(peer.host, peer.port, wire) }
        val queued = outcome != SendOutcome.DELIVERED && OutboxPolicy.isQueueable(body)
        Mb10Log.event(TAG, "chat.send_direct", "to" to Mb10Log.short(peerPubKeyB64), "peerVisible" to (peer != null), "outcome" to outcome.name, "queued" to queued, "chars" to body.length)
        // Не ушло (адресата не видно или обрыв на роуминге) — в очередь: уйдёт само, когда он появится. Деньги/предметы не queue-им, см. OutboxPolicy.
        if (queued) OutboxStore.enqueue(context, peerPubKeyB64, wire)
        return outcome
    }

    /**
     * Чек получателя фиксирует платёж при ПРИЁМЕ, а не пока у отправителя открыт этот тред: раньше
     * подтверждение делал только DirectThread, и если отправитель сидел на вкладке "Финансы", платёж
     * навсегда оставался "ждёт принятия".
     */
    private suspend fun confirmIfReceipt(context: Context, message: ChatWireMessage) {
        if (message.type != ChatMessageType.DM) return
        val receipt = Mb10QrCodec.decode(message.body) as? Mb10Qr.Receipt ?: return
        // Один и тот же чек подтверждает и деньги, и передачу предмета: id из разных журналов не пересекаются.
        val money = TransactionStore.verifyAndConfirmReceipt(context, receipt.id, receipt)
        val item = ItemTransferStore.verifyAndConfirmReceipt(context, receipt.id, receipt)
        Mb10Log.event(TAG, "receipt.in", "id" to receipt.id, "from" to Mb10Log.short(receipt.receiverPubKeyB64), "confirmedMoney" to money, "confirmedItem" to item)
    }

    /** Сохраняет входящее, если такого ещё нет (тот же отправитель, время, тип и текст). false — это повтор. */
    private suspend fun persistIfNew(context: Context, message: ChatWireMessage): Boolean {
        val dao = Mb10Database.get(context).chatMessageDao()
        if (dao.countSame(message.fromPubKeyB64, message.timestamp, message.type.name, message.body) > 0) return false
        persist(context, message)
        return true
    }

    private suspend fun persist(context: Context, message: ChatWireMessage) {
        Mb10Database.get(context).chatMessageDao().insert(
            ChatMessageEntity(
                type = message.type.name,
                fromPubKeyB64 = message.fromPubKeyB64,
                fromCallsign = message.fromCallsign,
                faction = message.fromFaction,
                toPubKeyB64 = message.toPubKeyB64,
                body = message.body,
                timestamp = message.timestamp
            )
        )
    }
}
