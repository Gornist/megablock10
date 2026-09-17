package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.PendingAlertEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Сигнал СБ игроку-владельцу узла — ревизия v9 §4-5. Не отдельный QR, а
 * тело обычного фракционного чат-сообщения от системного псевдо-контакта
 * "SEC//MB10" (см. ChatScreen.MessageBubble — тот же приём, что у платёжной
 * карточки: msg.body декодируется через Mb10QrCodec и рендерится особо).
 * Отложенные сообщения стоят в очереди (PendingAlertEntity) на устройстве
 * взломщика до sendAt, дальше пытаются уйти при каждом изменении списка
 * видимых пиров, пока не истечёт ttl.
 */
object SecAlertStore {
    private const val AGG_WINDOW_MS = 15 * 60_000L
    private const val TTL_MS = 30 * 60_000L
    private const val SYSTEM_PUBKEY = "SEC-SYSTEM"
    private const val SYSTEM_CALLSIGN = "SEC//MB10"

    /** containerId → окно агрегации: полное сообщение раз в 15 минут, дальше счётчик повторов. Живёт в памяти на время сессии приложения — не переживает перезапуск, это осознанно (см. ревизию v9 §4). */
    private val aggregation = ConcurrentHashMap<String, AggState>()
    private data class AggState(var lastFullSentAt: Long = 0, var suppressed: Int = 0)

    fun start(context: Context, scope: CoroutineScope) {
        scope.launch {
            PresenceService.peers.collect { flush(context) }
        }
    }

    /**
     * Ставит сигнал в очередь по правилам ревизии v9 §4: FAIL на тире BASE
     * сигнала не даёт вовсе; BLACKOUT среди совпавших эффектов гасит его
     * полностью; TIMESKEW добавляет 10 минут к задержке; GHOST убирает
     * позывной взломщика из содержимого, даже если тир его обычно раскрывает.
     * Взлом собственного узла (ownerFaction игрока-взломщика) сигнала не даёт.
     */
    suspend fun dispatch(context: Context, identity: Identity, container: Container, outcome: BreachOutcome, matchedEffects: Set<DaemonEffect>) {
        if (container.ownerFaction.isBlank() || container.ownerFaction == identity.faction) return
        if (outcome == BreachOutcome.FAIL && container.tier == Tier.BASE) return
        if (DaemonEffect.BLACKOUT in matchedEffects) return

        val baseDelayMs = if (container.tier == Tier.NIGHTMARE) 0L else 2 * 60_000L
        val timeskewBonus = if (DaemonEffect.TIMESKEW in matchedEffects) 10 * 60_000L else 0L
        val now = System.currentTimeMillis()
        val sendAt = now + baseDelayMs + timeskewBonus

        val revealCallsign = container.tier != Tier.BASE && DaemonEffect.GHOST !in matchedEffects
        val revealPreciseTime = container.tier == Tier.NIGHTMARE
        val alert = Mb10Qr.SecurityAlert(
            containerId = container.id,
            containerName = container.name,
            tier = container.tier.level,
            intruderCallsign = if (revealCallsign) identity.callsign else null,
            preciseAt = if (revealPreciseTime) now else null
        )

        Mb10Database.get(context).pendingAlertDao().insert(
            PendingAlertEntity(
                containerId = container.id,
                containerName = container.name,
                faction = container.ownerFaction,
                payload = Mb10QrCodec.encodeSecurityAlert(alert),
                sendAt = sendAt,
                ttl = now + TTL_MS
            )
        )
        flush(context)
    }

    suspend fun flush(context: Context) {
        val dao = Mb10Database.get(context).pendingAlertDao()
        val now = System.currentTimeMillis()
        dao.deleteExpired(now)
        val onlineFactions = PresenceService.peers.value.map { it.faction }.toSet()
        dao.all().filter { it.sendAt <= now && it.faction in onlineFactions }.forEach { pending ->
            sendNow(context, pending)
            dao.delete(pending)
        }
    }

    private suspend fun sendNow(context: Context, pending: PendingAlertEntity) {
        val body = aggregatedBody(pending)
        val systemIdentity = Identity(publicKeyB64 = SYSTEM_PUBKEY, callsign = SYSTEM_CALLSIGN, faction = pending.faction)
        ChatStore.sendFaction(context, systemIdentity, body)
    }

    /** Полное структурированное сообщение раз в 15 минут на контейнер, иначе однострочный счётчик повторов. */
    private fun aggregatedBody(pending: PendingAlertEntity): String {
        val state = aggregation.getOrPut(pending.containerId) { AggState() }
        val now = System.currentTimeMillis()
        if (now - state.lastFullSentAt >= AGG_WINDOW_MS) {
            state.lastFullSentAt = now
            state.suppressed = 0
            return pending.payload
        }
        state.suppressed += 1
        return "Повторные обращения к узлу «${pending.containerName}» (×${state.suppressed + 1})"
    }
}
