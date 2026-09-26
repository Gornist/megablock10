package com.megablok10.app.chat

import android.content.Context
import com.megablok10.app.breach.SlotClaimStore
import com.megablok10.app.call.CallManager
import com.megablok10.app.identity.Identity
import com.megablok10.app.items.ItemLedger
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.presence.MeshForegroundService
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.presence.WifiBinder
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.sound.SoundPlayer
import com.megablok10.app.wallet.PaymentLedger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "ChatStore"

/**
 * Сетевая сессия персонажа — всё, что должно работать, пока у телефона есть личность, даже когда игрок на другой вкладке или
 * приложение свёрнуто: сервер строк на приём (чат, звонки, заявки на слот — ChatServer), объявление себя и поиск других в сети
 * (PresenceService/NSD), привязка трафика к Wi-Fi площадки (WifiBinder), foreground-сервис, чтобы Android не заморозил процесс,
 * досылка очереди исходящих и фоновые задачи сессии ([sessionTasks]: отложенные сигналы СБ, снимок состояния в журнал).
 *
 * Запускается на время жизни личности (корень приложения зовёт [start] при появлении персонажа, сброс сессии — [stop]); повторный
 * [start] для той же личности — не операция. [start] синхронный (его удобно звать с главного потока), всё блокирующее — bind
 * сокета, регистрация NSD — уходит в свой скоуп на Dispatchers.IO.
 */
// Приёмники всех входящих протоколов собраны здесь, в корне композиции; разобрать сессию на части — B3 (SessionController).
@Suppress("LongParameterList")
class MeshSession(
    private val app: Context,
    private val chat: ChatStore,
    private val presence: PresenceService,
    private val wifi: WifiBinder,
    private val calls: CallManager,
    private val slotClaims: SlotClaimStore,
    private val receipts: ReceiptConfirmer,
    private val readReceipts: ReadReceipts,
    /** Строка известного протокола, но другой версии (телефон со старым/новым приложением) — сказать игроку (kit IncompatibleVersionReporter). */
    private val onIncompatible: (String) -> Unit,
    /** Фоновые задачи на время сессии (отложенные сигналы СБ, снимки состояния): стартуют после сервера, гаснут с сессией. */
    private val sessionTasks: List<(CoroutineScope) -> Unit>,
) {
    private var server: ChatServer? = null
    private var scope: CoroutineScope? = null
    private var startedForKey: String? = null

    /** Порт, на котором сейчас слушает приложение (-1 — не запущен). Нужен heartbeat коллектору и стенду e2e (связать эмуляторы). */
    val listeningPort: Int get() = server?.port ?: -1

    @Synchronized
    fun start(identity: Identity) {
        if (startedForKey == identity.publicKeyB64) return
        stop()
        startedForKey = identity.publicKeyB64
        Mb10Log.event(TAG, "chat.start", "me" to Mb10Log.short(identity.publicKeyB64), "callsign" to identity.callsign, "faction" to identity.faction)

        val sessionScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope = sessionScope

        SoundPlayer.preload(app)
        // Без этого фоновый процесс рано или поздно замораживается, и приём сообщений/звонков встаёт до открытия приложения заново.
        MeshForegroundService.start(app)
        // Трафик приложения — только по Wi-Fi игровой сети; при смене сети NSD перерегистрируется (docs/network-spec.md, §7).
        wifi.start { presence.refresh() }

        sessionScope.launch {
            val srv = ChatServer(
                // Сохранение — до возврата: отправитель получит «доставлено» только после него (D2). Звук и уведомление — потом.
                onMessage = { msg ->
                    onChatMessage(msg)
                    // Звук — только для реально пришедших по сети сообщений (этот колбэк
                    // и есть приём с провода), свои же исходящие не должны пищать.
                    SoundPlayer.playMessageReceived(app)
                },
                onCallSignal = { signal -> calls.onSignalReceived(identity, signal) },
                onSlotClaim = { claim -> slotClaims.receive(claim) },
                onReadReceipt = { r -> readReceipts.onReceived(identity.publicKeyB64, r) },
                onIncompatible = onIncompatible,
                myKey = { identity.publicKeyB64 },
                onHeard = presence::heard,
            )
            srv.start(sessionScope)
            server = srv
            presence.start(identity, srv.port)
            sessionTasks.forEach { it(sessionScope) }
        }

        // Очередь исходящих: досылаем, как только адресат снова виден, и по таймеру (для повторов с паузой).
        sessionScope.launch { presence.peers.collect { chat.flushOutbox() } }
        sessionScope.launch { while (true) { delay(5_000); chat.flushOutbox() } }
    }

    /** Сессия уже идёт — убедиться, что foreground-сервис поднят: при старте из фона Android 12+ мог его не пустить. Зовёт экран. */
    @Synchronized
    fun ensureForeground() {
        if (startedForKey != null) MeshForegroundService.start(app)
    }

    @Synchronized
    fun stop() {
        Mb10Log.event(TAG, "chat.stop")
        server?.stop()
        presence.stop()
        wifi.stop()
        if (startedForKey != null) MeshForegroundService.stop(app)
        scope?.cancel()
        server = null
        scope = null
        startedForKey = null
    }

    private suspend fun onChatMessage(msg: ChatWireMessage) {
        // Повторная доставка того же сообщения (отправитель не увидел подтверждения и переслал из очереди) не дублируется.
        val fresh = chat.receive(msg)
        Mb10Log.event(TAG, "chat.recv", "type" to msg.type.name, "from" to Mb10Log.short(msg.fromPubKeyB64), "chars" to msg.body.length, "duplicate" to !fresh, "ageMs" to (System.currentTimeMillis() - msg.timestamp))
        if (!fresh) return
        receipts.onIncoming(msg)
        ChatNotifier.show(app, msg)
    }
}

/**
 * Чек получателя фиксирует перевод или передачу предмета при ПРИЁМЕ, а не пока у отправителя открыт тред: раньше подтверждение
 * делал только экран треда, и если отправитель сидел на вкладке "Финансы", платёж навсегда оставался "ждёт принятия".
 */
class ReceiptConfirmer(private val payments: PaymentLedger, private val items: ItemLedger) {
    suspend fun onIncoming(message: ChatWireMessage) {
        if (message.type != ChatMessageType.DM) return
        val receipt = Mb10QrCodec.decode(message.body) as? Mb10Qr.Receipt ?: return
        val (money, item) = confirm(receipt)
        Mb10Log.event(TAG, "receipt.in", "id" to receipt.id, "from" to Mb10Log.short(receipt.receiverPubKeyB64), "confirmedMoney" to money, "confirmedItem" to item)
    }

    /**
     * Один и тот же чек подтверждает и деньги, и передачу предмета: id из разных журналов не пересекаются. Повтор безопасен (переход
     * только из DELIVERED/PENDING), поэтому тред при открытии перепроверяет чеки из истории — без записи в журнал.
     * Возвращает пару «подтверждён перевод» к «подтверждена передача предмета».
     */
    suspend fun confirm(receipt: Mb10Qr.Receipt): Pair<Boolean, Boolean> =
        payments.verifyAndConfirmReceipt(receipt.id, receipt) to items.verifyAndConfirmReceipt(receipt.id, receipt)
}
