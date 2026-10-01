package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.handover.Handover
import com.megablok10.kit.handover.OutgoingJournal
import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.net.SendOutcome
import com.megablok10.netrun.bridge.Doc
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.HandoverGateway
import com.megablok10.netrun.bridge.IssuedTransfer
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueOps
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonNull

/** Что выдаём: предмет (документ `item` в `outbox:*`) или эдди (документ `payout`). */
private class Outgoing(val id: String, val runner: String, val doc: Doc, val isItem: Boolean)

/**
 * Журнал исходящих карточек Моста для kit [Handover] поверх документов: статус карточки — `item.handover` (`PENDING` →
 * `DELIVERED`) или `payout.state`; подтверждённый чеком предмет переходит к `phone:<ключ>` (`handover` = null), выплата — в `CONFIRMED`.
 * Каждый переход условный и одной транзакцией, как у приложения.
 */
internal class WorldJournal(private val store: DocStore) : OutgoingJournal {
    override suspend fun markDelivered(id: String): Int = move(id, from = "PENDING", to = "DELIVERED")

    override suspend fun markUndelivered(id: String): Int = move(id, from = "DELIVERED", to = "PENDING")

    override suspend fun confirm(id: String): Int = store.transaction { tx ->
        val item = findItem(tx, id)
        if (item != null) {
            val owner = VJ.str(item.data, "owner").orEmpty()
            val state = VJ.str(item.data, "handover")
            if (!owner.startsWith(OUTBOX) || state == null) return@transaction 0
            val data = VJ.with(item.data, "owner" to VJ.p(PHONE + owner.removePrefix(OUTBOX)), "handover" to JsonNull)
            tx.put(ValueOps.ITEM, item.id, item.ver, data)
            return@transaction 1
        }
        val pay = tx.get(ValueOps.PAYOUT, id) ?: return@transaction 0
        if (VJ.str(pay.data, "state") == "CONFIRMED") return@transaction 0
        tx.put(ValueOps.PAYOUT, id, pay.ver, VJ.with(pay.data, "state" to VJ.p("CONFIRMED")))
        1
    }

    /** Адресат карточки [id]: хозяин `outbox:`/`phone:` предмета либо `runner` выплаты; null — такой выдачи нет. */
    override suspend fun recipientOf(id: String): String? = store.transaction { tx ->
        val item = findItem(tx, id)
        if (item != null) {
            val owner = VJ.str(item.data, "owner").orEmpty()
            return@transaction owner.removePrefix(OUTBOX).removePrefix(PHONE).takeIf { owner.startsWith(OUTBOX) || owner.startsWith(PHONE) }
        }
        tx.get(ValueOps.PAYOUT, id)?.let { VJ.str(it.data, "runner") }
    }

    private fun move(id: String, from: String, to: String): Int = store.transaction { tx ->
        val item = findItem(tx, id)
        if (item != null) {
            if (VJ.str(item.data, "handover") != from) return@transaction 0
            tx.put(ValueOps.ITEM, item.id, item.ver, VJ.with(item.data, "handover" to VJ.p(to)))
            return@transaction 1
        }
        val pay = tx.get(ValueOps.PAYOUT, id) ?: return@transaction 0
        if (VJ.str(pay.data, "state") != from) return@transaction 0
        tx.put(ValueOps.PAYOUT, id, pay.ver, VJ.with(pay.data, "state" to VJ.p(to)))
        1
    }

    private fun findItem(tx: DocStore.Tx, id: String): Doc? =
        store.list(ValueOps.ITEM).firstOrNull { VJ.str(it.data, "out_transfer") == id }?.let { tx.get(ValueOps.ITEM, it.id) }

    companion object {
        const val OUTBOX = "outbox:"
        const val PHONE = "phone:"
    }
}

/**
 * Выдача на телефон (M2): настоящая реализация [HandoverGateway]. Карточки предметов и эдди подписываются [key], уходят через
 * kit [Handover] (DELIVERED ставится ДО отправки, откат в PENDING — только при NOT_REACHED) и считаются доставленными по чеку.
 *
 * Источник правды — документы (`outbox:*` с `handover` PENDING/DELIVERED и `payout` в PENDING/DELIVERED), а не список из
 * [issued]: тот только будит [flush], поэтому потерянный вызов или рестарт Моста ничего не теряют — [flush] при старте и по
 * таймеру досылает всё, что не подтверждено. UNKNOWN («могло дойти») статус не откатывает и по другому адресу не повторяется
 * (это делает [PhoneSender]); карточка в DELIVERED без чека переотправляется через [resendAfterMs] тем же порядком адресов — получатель
 * по id отсекает повтор и снова отвечает чеком.
 */
class PhoneDelivery(
    private val store: DocStore,
    private val key: WorldKey,
    private val sender: PhoneSender,
    private val clock: () -> Long = System::currentTimeMillis,
    private val log: KitLog = NoopLog,
    private val scope: CoroutineScope? = null,
    private val resendAfterMs: Long = DEFAULT_RESEND_MS,
) : HandoverGateway {
    private val journal = WorldJournal(store)
    private val handover = Handover(journal, log, tag = TAG, eventPrefix = "bridge")
    private val lock = Mutex()
    private val lastAttempt = HashMap<String, Long>()

    /** Вызывается после коммита операции: будит отправку в [scope] (нет скоупа — отправку делает [flush] по таймеру/из теста). */
    override fun issued(transfers: List<IssuedTransfer>) {
        scope?.launch { flush() }
    }

    /** Чек телефона: фиксирует выдачу, если подписан адресатом этой карточки (иначе чужой чек молча отбрасывается). */
    suspend fun onReceipt(receipt: ReceiptCard): Boolean =
        // Без замка [flush]: телефон может ответить чеком, пока отправка ещё ждёт его же квитанцию (иначе взаимная блокировка).
        handover.confirmByReceipt(receipt.id, receipt.id, receipt.receiver, receipt.signature)

    /** Отправляет всё неподтверждённое (PENDING — впервые, DELIVERED — повтором по таймеру). Возвращает число попыток отправки. */
    suspend fun flush(): Int = lock.withLock {
        val due = pending().filter { isDue(it) && sender.isOnline(it.runner) }
        for (t in due) attempt(t)
        due.size
    }

    /** PENDING уходит сразу; DELIVERED без чека — не чаще раза в [resendAfterMs] (после рестарта Моста сразу). */
    private fun isDue(t: Outgoing): Boolean {
        val last = lastAttempt[t.id]
        return isNew(t) || last == null || clock() - last >= resendAfterMs
    }

    private fun isNew(t: Outgoing) = VJ.str(t.doc.data, if (t.isItem) "handover" else "state") == "PENDING"

    private suspend fun attempt(t: Outgoing) {
        try {
            if (isNew(t)) handover.deliver(t.id, willSend = true) { send(t) } else resend(t)
        } catch (e: Exception) {
            // Сбой посреди отправки: статус уже DELIVERED (ставится до отправки) — это «могло дойти», не откатываем.
            log.warnEvent(TAG, "bridge.deliver_failed", "id" to t.id, "error" to e.javaClass.simpleName)
        }
        lastAttempt[t.id] = clock()
    }

    private suspend fun resend(t: Outgoing) {
        val outcome = send(t)
        log.event(TAG, "bridge.resend", "id" to t.id, "outcome" to outcome.name)
    }

    private suspend fun send(t: Outgoing): SendOutcome {
        val body = if (t.isItem) PhoneWire.encodeItem(itemCard(t)) else PhoneWire.encodeMoney(moneyCard(t))
        val dm = ChatDm(key.publicB64, BRIDGE_CALLSIGN, "", t.runner, clock(), body)
        return withContext(Dispatchers.IO) { sender.send(t.runner, PhoneWire.encodeChat(dm)) }
    }

    private fun itemCard(t: Outgoing): ItemCard {
        val unsigned = ItemCard(t.id, key.publicB64, t.runner, VJ.str(t.doc.data, "kind").orEmpty(), VJ.str(t.doc.data, "payload").orEmpty(), "")
        return unsigned.copy(signature = key.sign(PhoneWire.itemSignedBytes(unsigned)))
    }

    private fun moneyCard(t: Outgoing): MoneyCard {
        val amount = VJ.lng(t.doc.data, "eddies")
        return MoneyCard(t.id, key.publicB64, t.runner, amount, PAYOUT_MEMO, key.sign(PhoneWire.moneySignedBytes(t.id, key.publicB64, t.runner, amount, PAYOUT_MEMO)))
    }

    private fun unconfirmed(state: String?) = state == "PENDING" || state == "DELIVERED"

    private fun pending(): List<Outgoing> {
        val items = store.list(ValueOps.ITEM).mapNotNull { d ->
            val owner = VJ.str(d.data, "owner").orEmpty()
            val tid = VJ.str(d.data, "out_transfer")
            if (owner.startsWith(WorldJournal.OUTBOX) && tid != null && unconfirmed(VJ.str(d.data, "handover"))) {
                Outgoing(tid, owner.removePrefix(WorldJournal.OUTBOX), d, true)
            } else {
                null
            }
        }
        val pays = store.list(ValueOps.PAYOUT).filter { unconfirmed(VJ.str(it.data, "state")) }
            .map { Outgoing(it.id, VJ.str(it.data, "runner").orEmpty(), it, false) }
        return items + pays
    }

    companion object {
        const val TAG = "BridgeHandover"
        const val DEFAULT_RESEND_MS = 30_000L
        private const val BRIDGE_CALLSIGN = "Мост"
        private const val PAYOUT_MEMO = "Добыча из Сети"
    }
}
