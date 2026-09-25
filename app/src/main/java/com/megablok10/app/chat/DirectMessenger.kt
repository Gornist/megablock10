package com.megablok10.app.chat

import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.net.SendOutcome

/**
 * Личные сообщения глазами сценариев передачи (переводы, предметы, чеки): кто из игроков сейчас виден и как ему отправить.
 * Реализация — [ChatStore]; в тестах сценариев — фейк.
 */
interface DirectMessenger {
    /** Игрок, если он сейчас виден в сети; null — не в сети (сообщение всё равно останется в треде). Адрес выбирает PeerDirectory. */
    fun onlinePeer(pubKeyB64: String): OnlinePlayer?

    /** true — адресат точно получил строку. См. [ChatStore.sendDirect]. */
    suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, peer: OnlinePlayer?, body: String): Boolean

    /** С различением «точно не ушло» и «могло уйти» — нужно деньгам и предметам (kit handover). См. [ChatStore.sendDirectOutcome]. */
    suspend fun sendDirectOutcome(identity: Identity, peerPubKeyB64: String, peer: OnlinePlayer?, body: String): SendOutcome
}

/**
 * Доставка подписанной карточки (перевод, предмет) адресату по протоколу kit handover: [track] — deliverOutgoing журнала
 * (DELIVERED ставится до отправки, откат — только при NOT_REACHED). Адрес берём в момент доставки. [offline] — считать адресата
 * невидимым, даже если он в сети (стенд e2e: «получатель не в сети»); карточка тогда лишь ляжет в свой тред.
 */
suspend fun DirectMessenger.deliverCard(
    me: Identity,
    toPubKeyB64: String,
    wire: String,
    offline: Boolean,
    track: suspend (willSend: Boolean, send: suspend () -> SendOutcome) -> Unit,
) {
    val peer = if (offline) null else onlinePeer(toPubKeyB64)
    track(peer != null) { sendDirectOutcome(me, toPubKeyB64, peer, wire) }
}

/** Чек получателя — ответ отправителю в личку. Адрес ищем сейчас: пока игрок принимал, отправитель мог появиться или пропасть. */
suspend fun DirectMessenger.sendReceipt(me: Identity, toPubKeyB64: String, receipt: Mb10Qr.Receipt): Boolean =
    sendDirect(me, toPubKeyB64, onlinePeer(toPubKeyB64), Mb10QrCodec.encodeReceipt(receipt))
