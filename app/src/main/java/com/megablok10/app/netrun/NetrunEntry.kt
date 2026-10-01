package com.megablok10.app.netrun

import com.megablok10.app.breach.Daemon
import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.chat.deliverCard
import com.megablok10.app.identity.Identity
import com.megablok10.app.items.ItemLedger
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

private const val TAG = "Netrun"

/** Где игрок на пути «стойка → очки». */
sealed interface NetrunEntryState {
    /** Ничего не идёт: экран выбора деки показывает сам себя, пока есть отсканированная стойка. */
    data object Idle : NetrunEntryState

    /** Карточки демонов уходят Мосту. */
    data class Sending(val rack: Mb10Qr.Rack) : NetrunEntryState

    /** Карточки у Моста, запрос входа отправлен, ждём подписанный `MB10ENTERED`. */
    data class Waiting(val rack: Mb10Qr.Rack, val timedOut: Boolean = false) : NetrunEntryState

    /** Мост собрал деку: «Подключено к стойке N, надень очки». */
    data class Connected(val rack: Mb10Qr.Rack, val session: String) : NetrunEntryState

    /** Отказ или сбой; [text] — что сказать игроку. */
    data class Failed(val text: String) : NetrunEntryState
}

/**
 * Вход в «Сеть» (M3, docs/netrun-bridge-protocol.md, раздел 8): карточки выбранных демонов уходят Мосту как обычные передачи
 * предметов игроку (адресат — ключ мира из QR стойки, адрес Моста — статический пир), следом — подписанный запрос `MB10ENTER`, потом
 * ждём подписанный `MB10ENTERED`. Всё про ценности — прежние сценарии и kit Handover: демон уходит из коллекции сразу (PENDING),
 * `NOT_REACHED` возвращает его отменой, `UNKNOWN` («могло дойти») не откатывается и не повторяется по другому адресу.
 *
 * Запрос без ответа повторяется с тем же `rid` ([RETRY_MS]) — Мост отвечает из сохранённого результата. Демоны, сданные Мосту без
 * входа (отказ, таймаут), Мост сам возвращает карточками; их принимает [WorldAutoAccept].
 */
class NetrunEntry(
    private val store: NetrunStore,
    private val ledger: ItemLedger,
    private val messenger: DirectMessenger,
    /** Строка Мосту без обёртки чата (блокирует поток: звать с IO). */
    private val sendLine: (toKey: String, line: String) -> SendOutcome,
    private val addPeer: (PeerInfo) -> Unit,
    private val sign: (ByteArray) -> String,
    private val work: CoroutineScope,
    private val verify: (publicKeyB64: String, data: ByteArray, signatureB64: String) -> Boolean = Ecdsa::verify,
    private val now: () -> Long = System::currentTimeMillis,
    private val newRid: () -> String = { "e-" + UUID.randomUUID().toString().take(RID_CHARS) },
    private val retryMs: Long = RETRY_MS,
    private val waitMs: Long = WAIT_MS,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val _state = MutableStateFlow<NetrunEntryState>(store.attempt()?.let { NetrunEntryState.Waiting(it.rack, timedOut = true) } ?: NetrunEntryState.Idle)
    val state: StateFlow<NetrunEntryState> = _state.asStateFlow()

    /** Игрок отсканировал стойку: запоминаем её (ключ мира нужен приёму добычи) и ставим адрес Моста. */
    fun onRackScanned(rack: Mb10Qr.Rack) {
        store.saveRack(rack)
        registerPeer(rack)
        Mb10Log.event(TAG, "netrun.rack_scanned", "terminal" to rack.terminal, "world" to Mb10Log.short(rack.worldPub), "addr" to "${rack.host}:${rack.port}")
    }

    /** Адрес Моста в таблицу пиров (при старте сессии — тоже: статическая запись переживает не всё). */
    fun registerPeer(rack: Mb10Qr.Rack) = addPeer(PeerInfo(rack.worldPub, WORLD_CALLSIGN, "", rack.host, rack.port))

    fun restorePeer() { store.rack()?.let(::registerPeer) }

    /**
     * Сдать [daemons] (защищённый — [protectedId]) на терминал стойки [rack]. Правила: хоть один демон, защищённый среди них, все
     * передаваемые, вместе помещаются в RAM деки. Результат — через [state].
     */
    suspend fun enter(me: Identity, rack: Mb10Qr.Rack, daemons: List<Daemon>, protectedId: String) {
        if (_state.value is NetrunEntryState.Sending) return
        val problem = validate(me, daemons, protectedId)
        if (problem != null) { _state.value = NetrunEntryState.Failed(problem); return }
        onRackScanned(rack)
        _state.value = NetrunEntryState.Sending(rack)
        Mb10Log.event(TAG, "netrun.enter_start", "terminal" to rack.terminal, "daemons" to daemons.size)

        val transfers = mutableListOf<String>()
        var protectedTransfer = ""
        for (daemon in daemons) {
            val card = ledger.sendDaemon(me, daemon, rack.worldPub)
            if (card == null) { _state.value = failedAfter(transfers.size, "Демон «${daemon.name}» не удалось передать."); return }
            var outcome = SendOutcome.NOT_REACHED
            messenger.deliverCard(me, rack.worldPub, Mb10QrCodec.encodeItemTransfer(card), offline = false) { willSend, send ->
                ledger.deliverOutgoing(card.id, willSend) { send().also { outcome = it } }
            }
            Mb10Log.event(TAG, "netrun.card_sent", "id" to card.id, "outcome" to outcome.name)
            if (outcome == SendOutcome.NOT_REACHED) {
                ledger.cancelOutgoing(card.id) // точно не ушла — демон возвращается в коллекцию
                _state.value = failedAfter(transfers.size, "Мост не отвечает. Проверьте, что вы в сети площадки.")
                return
            }
            transfers += card.id
            if (daemon.id == protectedId) protectedTransfer = card.id
        }

        val unsigned = EnterRequest(newRid(), rack.terminal, me.publicKeyB64, me.callsign, transfers, protectedTransfer, now())
        val request = unsigned.copy(signature = sign(NetrunWire.enterSignedBytes(unsigned)))
        store.saveAttempt(request)
        _state.value = NetrunEntryState.Waiting(rack)
        Mb10Log.event(TAG, "netrun.enter_sent", "rid" to request.rid, "terminal" to rack.terminal, "transfers" to transfers.size)
        work.launch { retryLoop(request) }
    }

    /** Ответ Моста: подпись ключом мира из QR стойки; чужой, поддельный или повторный ответ молча отбрасывается. */
    fun onEntered(reply: EnterReply) {
        val attempt = store.attempt()
        if (attempt == null || attempt.request.rid != reply.rid) {
            Mb10Log.warnEvent(TAG, "netrun.entered_ignored", "rid" to reply.rid, "why" to "нет такого запроса")
            return
        }
        if (!verify(attempt.rack.worldPub, NetrunWire.enteredSignedBytes(reply), reply.signature)) {
            Mb10Log.warnEvent(TAG, "netrun.entered_ignored", "rid" to reply.rid, "why" to "подпись не сошлась")
            return
        }
        store.clearAttempt()
        Mb10Log.event(TAG, "netrun.entered", "rid" to reply.rid, "ok" to reply.ok, "code" to reply.code.ifEmpty { null })
        _state.value = if (reply.ok) {
            NetrunEntryState.Connected(attempt.rack, reply.session)
        } else {
            NetrunEntryState.Failed("Вход отклонён: ${reply.msg.ifEmpty { reply.code }}. Деки вернутся на телефон.")
        }
    }

    /** Повторить запрос без ответа (тот же `rid`); для экрана «Мост не ответил». */
    fun retry() {
        val attempt = store.attempt() ?: return
        _state.value = NetrunEntryState.Waiting(attempt.rack)
        work.launch { retryLoop(attempt.request) }
    }

    /** Закрыть результат или отказаться ждать. Запрос без ответа забывается: поздний ответ Моста уже не принимается. */
    fun dismiss() {
        if (_state.value is NetrunEntryState.Waiting) store.clearAttempt()
        _state.value = NetrunEntryState.Idle
    }

    private suspend fun retryLoop(request: EnterRequest) {
        val deadline = now() + waitMs
        val line = NetrunWire.encodeEnter(request)
        while (store.attempt()?.request?.rid == request.rid) {
            val outcome = withContext(io) { sendLine(store.worldPub().orEmpty(), line) }
            Mb10Log.event(TAG, "netrun.enter_line", "rid" to request.rid, "outcome" to outcome.name)
            delay(retryMs)
            if (store.attempt()?.request?.rid != request.rid) return
            if (now() > deadline) {
                (state.value as? NetrunEntryState.Waiting)?.let { _state.value = it.copy(timedOut = true) }
                return
            }
        }
    }

    private fun validate(me: Identity, daemons: List<Daemon>, protectedId: String): String? = when {
        daemons.isEmpty() -> "Выберите хотя бы одного демона."
        daemons.none { it.id == protectedId } -> "Выберите защищённого демона."
        daemons.any { !ItemTransferStore.isTransferable(it) } -> "Стартового демона в Сеть не отдать."
        daemons.sumOf { it.sequence.size } > me.ramCapacity -> "Демоны не помещаются в RAM деки."
        else -> null
    }

    private fun failedAfter(sent: Int, text: String) =
        NetrunEntryState.Failed(if (sent > 0) "$text Уже сданные демоны Мост вернёт на телефон." else text)

    companion object {
        const val RETRY_MS = 4_000L
        const val WAIT_MS = 120_000L
        private const val RID_CHARS = 12
        private const val WORLD_CALLSIGN = "Мост"
    }
}
