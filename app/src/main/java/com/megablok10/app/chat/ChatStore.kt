package com.megablok10.app.chat

import android.content.Context
import com.megablok10.app.breach.SecAlertStore
import com.megablok10.app.breach.SlotClaimStore
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.identity.Identity
import com.megablok10.app.call.CallManager
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Запускается один раз на время жизни приложения (из AppRoot, а не из
 * ChatScreen — вкладки Compose размонтируются при переключении, а входящие
 * сообщения должны приниматься и сохраняться, даже когда игрок на другой
 * вкладке). Держит сервер на приём + presence на обнаружение и знает, как
 * разослать/сохранить исходящее.
 */
object ChatStore {
    private var server: ChatServer? = null
    private var scope: CoroutineScope? = null
    private var startedForKey: String? = null

    /**
     * Сама функция синхронная (её удобно звать из LaunchedEffect на главном
     * потоке), но всё, что реально блокирует — bind сокета, регистрация
     * NSD — уходит в appScope на Dispatchers.IO, а не выполняется тут же.
     */
    fun start(context: Context, identity: Identity) {
        if (startedForKey == identity.publicKeyB64) return
        stop()
        startedForKey = identity.publicKeyB64

        val appContext = context.applicationContext
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope = appScope

        SoundPlayer.preload(appContext)

        appScope.launch {
            val srv = ChatServer(
                onMessage = { msg ->
                    appScope.launch {
                        persist(appContext, msg)
                        confirmIfReceipt(appContext, msg)
                    }
                    // Звук — только для реально пришедших по сети сообщений (этот колбэк
                    // и есть приём с провода), свои же исходящие persist() не должны пищать.
                    SoundPlayer.playMessageReceived(appContext)
                },
                onCallSignal = { signal -> CallManager.onSignalReceived(appContext, identity, signal) },
                onSlotClaim = { claim -> appScope.launch { SlotClaimStore.receive(appContext, claim) } }
            )
            srv.start(appScope)
            server = srv
            PresenceService.start(appContext, identity, srv.port)
            SecAlertStore.start(appContext, appScope)
        }
    }

    fun stop() {
        server?.stop()
        PresenceService.stop()
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
        withContext(Dispatchers.IO) {
            recipients.forEach { peer -> ChatClient.send(peer.host, peer.port, wire) }
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
    suspend fun sendDirect(context: Context, identity: Identity, peerPubKeyB64: String, peer: PeerInfo?, body: String): Boolean {
        val timestamp = System.currentTimeMillis()
        val wire = ChatWireMessage(ChatMessageType.DM, identity.publicKeyB64, identity.callsign, identity.faction, peerPubKeyB64, timestamp, body)
        persist(context, wire)
        if (peer == null) return false
        return withContext(Dispatchers.IO) { ChatClient.send(peer.host, peer.port, wire) }
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
        TransactionStore.verifyAndConfirmReceipt(context, receipt.id, receipt)
        ItemTransferStore.verifyAndConfirmReceipt(context, receipt.id, receipt)
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
