package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.handover.HandoverRules
import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.net.LineEnvelope
import com.megablok10.kit.net.LineRoute
import com.megablok10.kit.net.LineServer
import com.megablok10.kit.net.LineSocketClient
import com.megablok10.kit.net.SendOutcome
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueOps
import com.megablok10.netrun.bridge.ensureDefaultSettings
import com.megablok10.rules.Daemon
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.ShardPayload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import java.util.concurrent.CopyOnWriteArrayList

/** Телефон игрока на kit: свой ключ, сервер строк на localhost, карточки и чеки теми же форматами, что у приложения. */
class FakePhone(private val scope: CoroutineScope, private var worldPub: String, val log: RecordingLog = RecordingLog()) : AutoCloseable {
    private val pair = Ecdsa.generateKeyPair()
    val key: String = Ecdsa.encodeKey(pair.public)
    val bodies = CopyOnWriteArrayList<String>()
    val entered = CopyOnWriteArrayList<EnterReply>()

    /** Автоматически отвечать чеком на карточки Моста (как игрок, нажавший «Принять»). */
    @Volatile var autoReceipt = true
    private var bridgePort = 0
    private val client = LineSocketClient(log)
    private val server = LineServer(
        routes = listOf<LineRoute<*>>(
            LineRoute("chat", PhoneWire::decodeChat) { onChat(it) },
            LineRoute("entered", PhoneWire::decodeEntered) { entered.add(it) },
        ),
        identityKey = { key },
        io = Dispatchers.IO,
    )
    val port: Int get() = server.port

    init { server.start(scope) }

    fun connect(bridgePort: Int, worldPub: String = this.worldPub) { this.bridgePort = bridgePort; this.worldPub = worldPub }

    private fun onChat(dm: ChatDm) {
        bodies.add(dm.body)
        val id = PhoneWire.decodeItem(dm.body)?.id ?: PhoneWire.decodeMoney(dm.body)?.id
        // Чек уходит отдельно от обработчика, как после нажатия «Принять»: обработчик по возврату даёт Мосту квитанцию.
        if (id != null && autoReceipt) Thread { sendReceipt(id) }.start()
    }

    fun sendReceipt(id: String): SendOutcome =
        sendDm(PhoneWire.encodeReceipt(ReceiptCard(id, key, Ecdsa.sign(pair.private, HandoverRules.receiptSignaturePayload(id, key)))))

    fun sendDm(body: String): SendOutcome =
        sendLine(PhoneWire.encodeChat(ChatDm(key, "Призрак", "", worldPub, System.currentTimeMillis(), body)))

    fun sendLine(line: String): SendOutcome =
        client.sendLineOutcome("127.0.0.1", bridgePort, LineEnvelope(worldPub, key, port, line).encode(), expectAckFrom = worldPub)

    /** Карточка предмета [kind] из [payload] на ключ мира с подписью игрока. */
    fun itemCard(id: String, kind: String, payload: String, to: String = worldPub): ItemCard {
        val c = ItemCard(id, key, to, kind, payload, "")
        return c.copy(signature = Ecdsa.sign(pair.private, PhoneWire.itemSignedBytes(c)))
    }

    fun sendCard(card: ItemCard): SendOutcome = sendDm(PhoneWire.encodeItem(card))

    /** Запрос входа: [ram] = null — v1, иначе v2 с RAM персонажа. */
    fun enterRequest(rid: String, terminal: String, transfers: List<String>, protectedTransfer: String, ram: Int? = null): EnterRequest {
        val r = EnterRequest(rid, terminal, key, "Призрак", transfers, protectedTransfer, System.currentTimeMillis(), "", ram)
        return r.copy(signature = Ecdsa.sign(pair.private, PhoneWire.enterSignedBytes(r)))
    }

    fun sendEnter(r: EnterRequest): SendOutcome = sendLine(PhoneWire.encodeEnter(r))

    fun itemCards(): List<ItemCard> = bodies.mapNotNull { PhoneWire.decodeItem(it) }
    fun moneyCards(): List<MoneyCard> = bodies.mapNotNull { PhoneWire.decodeMoney(it) }

    override fun close() = server.stop()

    companion object {
        fun daemonPayload(id: String): String =
            ItemPayloadCodec.encodeDaemon(Daemon(id, "Демон $id", listOf("1C", "BD"), com.megablok10.rules.Tier.BASE))

        fun shardPayload(id: String): String =
            ItemPayloadCodec.encodeShard(ShardPayload(id, false, 1, "подсказка", "Шард $id", "мета", "тело", 0, true))
    }
}

/** Мост целиком без WebSocket: документы, выдача, приём и настоящий транспорт строк на localhost. */
class PhoneRig(path: String = ":memory:", val deliveryResendMs: Long = 60_000L, key: WorldKey = WorldKey.generate(), makeSender: ((PhoneNetwork) -> PhoneSender)? = null) : AutoCloseable {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val log = RecordingLog()
    val worldKey = key
    val store: DocStore = DocStore.open(path)
    lateinit var inbox: PhoneInbox
    val network = PhoneNetwork(worldKey, scope, { inbox.routes() }, 0, log)
    val sender: PhoneSender = makeSender?.invoke(network) ?: network
    val delivery = PhoneDelivery(store, worldKey, sender, log = log, scope = null, resendAfterMs = deliveryResendMs)
    val ops = ValueOps(store, gateway = delivery)
    val master = com.megablok10.netrun.bridge.Caller(com.megablok10.netrun.bridge.Role.MASTER, "master")
    val world = com.megablok10.netrun.bridge.Caller(com.megablok10.netrun.bridge.Role.WORLD, "world")

    init {
        inbox = PhoneInbox(store, ops, worldKey, sender, delivery, log = log)
        ensureDefaultSettings(store, worldKey.publicB64)
        if (store.get("node", "node_07") == null) {
            store.put("node", "node_07", 0, VJ.obj("tier" to VJ.p("STANDARD"), "lockdown_until" to VJ.p(0L), "eddies" to VJ.p(300L)))
            store.put("terminal", "t03", 0, VJ.obj("node" to VJ.p("node_07"), "label" to VJ.p("стойка 3")))
            store.put("terminal", "t04", 0, VJ.obj("node" to VJ.p("node_07"), "label" to VJ.p("стойка 4")))
        }
        network.start()
    }

    /** Телефон, знающий адрес Моста, и Мост, знающий адрес телефона (статическая запись, как QR стойки). */
    fun phone(tutorialDone: Boolean = true): FakePhone {
        val p = FakePhone(scope, worldKey.publicB64)
        p.connect(network.port)
        network.addStatic(p.key, "127.0.0.1", p.port)
        if (tutorialDone) {
            store.put("runner", ValueOps.runnerDocId(p.key), 0, VJ.obj("key" to VJ.p(p.key), "callsign" to VJ.p("Призрак"), "blocked" to VJ.p(false), "runs" to VJ.p(1L), "tutorial_done" to VJ.p(true)))
        }
        return p
    }

    fun item(id: String) = store.get("item", id)!!
    fun itemOf(transfer: String) = store.list("item").single { VJ.str(it.data, "in_transfer") == transfer }
    fun owner(docId: String) = VJ.str(item(docId).data, "owner")!!

    /** Ждёт [cond] до [seconds] с — все обмены асинхронны (чек уходит отдельным потоком). */
    fun await(what: String, seconds: Int = 10, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + seconds * 1000L
        while (!cond()) {
            check(System.currentTimeMillis() < end) { "не дождались: $what\n${log.all.joinToString("\n")}" }
            Thread.sleep(20)
        }
    }

    fun flush() = runBlocking { delivery.flush() }

    override fun close() {
        scope.cancel()
        network.close()
        store.close()
    }
}
