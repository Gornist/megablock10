package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.handover.HandoverRules
import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.log.shortKey
import com.megablok10.kit.net.LineRoute
import com.megablok10.netrun.bridge.Caller
import com.megablok10.netrun.bridge.Doc
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.ItemDecode
import com.megablok10.netrun.bridge.OpResult
import com.megablok10.netrun.bridge.Role
import com.megablok10.netrun.bridge.StoreException
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueOps
import com.megablok10.rules.ItemPayloadCodec
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import java.util.concurrent.ConcurrentHashMap

/**
 * Приём с телефона (M2, протокол Моста, раздел 8): Мост — получатель карточек предметов (сдача деки) по тем же правилам, что
 * телефон от другого игрока ([HandoverRules.rejectIncoming]: адресат — ключ мира, подпись сходится), с чеком; принятый
 * предмет — документ `item` в `inbox:<ключ>`. Потом телефон шлёт запрос входа ([EnterRequest]) — Мост зовёт `op.submit_deck`
 * и отвечает подписанным [EnterReply]. Чеки телефонов на выдачу уходят в [PhoneDelivery].
 *
 * Обработчик строки возвращается, только когда карточка записана в документы: по возврату телефону уходит `MB10ACK ok`. Сам чек
 * и ответ на вход отправляются после и не обязательны для приёма — не дошли, телефон повторит карточку или запрос (оба
 * идемпотентны: повтор карточки отсекает `in_transfer`, повтор запроса — `rid`).
 */
class PhoneInbox(
    private val store: DocStore,
    private val ops: ValueOps,
    private val key: WorldKey,
    private val sender: PhoneSender,
    private val delivery: PhoneDelivery,
    private val clock: () -> Long = System::currentTimeMillis,
    private val log: KitLog = NoopLog,
) {
    private val caller = Caller(Role.BRIDGE, "bridge")

    /** Один замок на сдачу деки, ответы и возврат: [sweep] и [tryEnter] не пересекаются, ответ на один `rid` — один. */
    private val entryLock = Any()

    /** Только для тестов: вызывается в [sweep] сразу под замком и после выборки просроченных, до возврата. */
    @Volatile internal var onSweepLocked: (() -> Unit)? = null
    @Volatile internal var afterStaleRead: (() -> Unit)? = null

    /** Запросы входа, которые ждут недостающие карточки (rid → запрос и время получения); при рестарте телефон шлёт запрос заново. */
    private val waiting = ConcurrentHashMap<String, Pair<EnterRequest, Long>>()

    /** Маршруты строк для сервера Моста: личные сообщения (карточки и чеки) и запросы входа. */
    fun routes(): List<LineRoute<*>> = listOf(
        LineRoute("chat", PhoneWire::decodeChat) { onChat(it) },
        LineRoute("enter", PhoneWire::decodeEnter) { onEnter(it) },
    )

    // ---------- карточки и чеки ----------

    internal suspend fun onChat(dm: ChatDm) {
        if (dm.to != key.publicB64) return
        PhoneWire.decodeItem(dm.body)?.let { acceptItem(dm.from, it); return }
        PhoneWire.decodeReceipt(dm.body)?.let { delivery.onReceipt(it); return }
        log.warnEvent(TAG, "bridge.in_ignored", "from" to shortKey(dm.from), "chars" to dm.body.length)
    }

    private suspend fun acceptItem(chatFrom: String, card: ItemCard) {
        val rejection = HandoverRules.rejectIncoming(card.from, card.to, key.publicB64, PhoneWire.itemSignedBytes(card), card.signature, Ecdsa::verify)
            ?: rejectContent(card)
            ?: chatFrom.takeIf { it != card.from }?.let { "отправитель чата не совпал с отправителем карточки" }
        if (rejection != null) {
            log.warnEvent(TAG, "bridge.in_rejected", "id" to card.id, "from" to shortKey(card.from), "why" to rejection)
            return
        }
        val created = store.transaction { tx ->
            val id = itemDocId(card)
            if (tx.get(ValueOps.ITEM, id) != null) return@transaction false
            tx.put(
                ValueOps.ITEM, id, 0,
                JsonObject(
                    VJ.obj(
                        "owner" to VJ.p("inbox:${card.from}"), "kind" to VJ.p(card.kind), "payload" to VJ.p(card.payload),
                        "protected" to VJ.p(false), "origin" to VJ.p("phone:${card.from}"), "in_transfer" to VJ.p(card.id),
                        "out_transfer" to JsonNull, "handover" to JsonNull,
                    ) + ItemDecode.fields(card.kind, card.payload), // daemon/shard — для сервера мира, он формата карточки не знает
                ),
            )
            true
        }
        log.event(TAG, "bridge.in_accepted", "id" to card.id, "from" to shortKey(card.from), "kind" to card.kind, "duplicate" to !created)
        // Чек — и на повтор карточки: прошлый мог не дойти. Не дошёл и этот — телефон повторит карточку.
        sendReceipt(card)
        waiting.values.filter { it.first.runner == card.from }.forEach { tryEnter(it.first) }
    }

    private fun rejectContent(card: ItemCard): String? = when {
        card.kind == "SHARD" && ItemPayloadCodec.decodeShard(card.payload) != null -> null
        card.kind == "DAEMON" && ItemPayloadCodec.decodeDaemon(card.payload) != null -> null
        else -> "содержимое не разобралось"
    }

    private fun sendReceipt(card: ItemCard) {
        val receipt = ReceiptCard(card.id, key.publicB64, key.sign(HandoverRules.receiptSignaturePayload(card.id, key.publicB64)))
        val dm = ChatDm(key.publicB64, CALLSIGN, "", card.from, clock(), PhoneWire.encodeReceipt(receipt))
        val outcome = runCatching { sender.send(card.from, PhoneWire.encodeChat(dm)) }.getOrNull()
        log.event(TAG, "bridge.receipt_sent", "id" to card.id, "outcome" to outcome?.name)
    }

    // ---------- вход ----------

    internal suspend fun onEnter(req: EnterRequest) {
        val signed = PhoneWire.enterSignedBytes(req)
        if (!Ecdsa.verify(req.runner, signed, req.signature)) {
            log.warnEvent(TAG, "bridge.enter_rejected", "rid" to req.rid, "why" to "подпись не сошлась")
            return
        }
        synchronized(entryLock) {
            waiting.putIfAbsent(req.rid, req to clock())
            tryEnter(req)
        }
    }

    /** Все карточки запроса уже в документах — сдаём деку (повтор по `rid` вернёт прежний ответ) и отвечаем телефону. */
    private fun tryEnter(req: EnterRequest) = synchronized(entryLock) {
        if (!waiting.containsKey(req.rid)) return@synchronized // уже получил ответ (в том числе тайм-аут из [sweep]) — второго, противоречащего, не шлём
        if (req.protectedTransfer !in req.transfers || req.transfers.isEmpty()) {
            return@synchronized reply(req, fail("bad_request", "защищённого демона нет среди переданных карточек"))
        }
        val items = req.transfers.map { tid -> store.list(ValueOps.ITEM).firstOrNull { VJ.str(it.data, "in_transfer") == tid && VJ.str(it.data, "origin") == "phone:${req.runner}" } }
        if (items.any { it == null }) return@synchronized // ждём остальные карточки
        val ids = items.map { it!!.id }
        val protectedId = items[req.transfers.indexOf(req.protectedTransfer)]!!.id
        val result = try {
            ops.submitDeck(caller, "enter:${req.rid}", req.runner, req.callsign, req.terminal, ids, protectedId)
        } catch (e: StoreException) {
            return@synchronized reply(req, fail(e.code, e.message.orEmpty()))
        }
        reply(req, if (result.ok) Triple(true, VJ.str(result.body, "session").orEmpty(), "" to "") else failOf(result))
    }

    private fun fail(code: String, msg: String) = Triple(false, "", code to msg)

    private fun failOf(r: OpResult) = Triple(false, "", r.code.orEmpty() to VJ.str(r.body, "msg").orEmpty())

    private fun reply(req: EnterRequest, result: Triple<Boolean, String, Pair<String, String>>) {
        waiting.remove(req.rid)
        val (ok, session, err) = result
        val sig = key.sign(PhoneWire.enteredSignedBytes(req.rid, ok, session, err.first, err.second))
        val line = PhoneWire.encodeEntered(EnterReply(req.rid, ok, session, err.first, err.second, sig))
        val dm = runCatching { sender.send(req.runner, line) }.getOrNull()
        log.event(TAG, "bridge.enter_reply", "rid" to req.rid, "ok" to ok, "code" to err.first.ifEmpty { null }, "outcome" to dm?.name)
    }

    // ---------- возврат и тайм-ауты ----------

    /**
     * Раз в период: запрос, не дождавшийся карточек за `inbox_timeout_s`, получает отказ `inbox_timeout`; карточки в `inbox`
     * старше срока и без ожидающего запроса возвращаются на телефон (`ValueOps.refundFromInbox`, `rid` = `refund:<in_transfer>`: только из `inbox`, проверка в транзакции).
     * Возвращает число возвращённых предметов. Выдачу потом отправляет [PhoneDelivery].
     */
    fun sweep(): Int = synchronized(entryLock) {
        onSweepLocked?.invoke()
        val settings = store.get(ValueOps.SETTINGS, "global")?.data ?: VJ.obj()
        val timeoutMs = if ("inbox_timeout_s" in settings) VJ.lng(settings, "inbox_timeout_s") * MS else DEFAULT_INBOX_MS
        val now = clock()
        waiting.values.filter { now - it.second > timeoutMs }.forEach { (req, _) -> reply(req, fail("inbox_timeout", "карточки не дошли вовремя")) }
        val claimed = waiting.values.flatMap { it.first.transfers }.toSet()
        val stale = store.list(ValueOps.ITEM).filter { d ->
            val transfer = VJ.str(d.data, "in_transfer")
            VJ.str(d.data, "owner").orEmpty().startsWith("inbox:") && transfer != null && transfer !in claimed && now - d.created > timeoutMs
        }
        afterStaleRead?.invoke()
        stale.count { refund(it) }
    }

    private fun refund(d: Doc): Boolean {
        val owner = VJ.str(d.data, "owner").orEmpty().removePrefix("inbox:")
        val transfer = VJ.str(d.data, "in_transfer").orEmpty()
        return try {
            // Только из inbox, проверка внутри транзакции: пока sweep считал, предмет могли сдать в деку (тогда пропуск).
            ops.refundFromInbox(caller, "refund:$transfer", owner, d.id).ok
        } catch (e: StoreException) {
            log.warnEvent(TAG, "bridge.refund_skipped", "id" to d.id, "code" to e.code)
            false
        }
    }

    private fun itemDocId(card: ItemCard): String = "it_" + VJ.sha256Hex("${card.from}|${card.id}").take(ID_HEX)

    companion object {
        const val TAG = "BridgeInbox"
        private const val CALLSIGN = "Мост"
        private const val MS = 1000L
        private const val DEFAULT_INBOX_MS = 300_000L
        private const val ID_HEX = 16
    }
}
