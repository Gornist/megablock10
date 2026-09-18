package com.megablok10.app.breach

import android.content.Context
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.PendingAlertEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

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

    /** Что решено про конкретный взлом — результат [decide], ещё без привязки к Context/БД. */
    data class AlertPlan(val sendAt: Long, val revealCallsign: Boolean, val revealPreciseTime: Boolean)

    /**
     * Правила ревизии v9 §4, вынесены в чистую функцию без Context/БД —
     * именно тут решается, будет ли сигнал вообще, и что в нём раскроется.
     * null — сигнала не будет: свой узел (ownerFaction взломщика), FAIL на
     * тире BASE, либо BLACKOUT среди совпавших эффектов гасит его полностью.
     * TIMESKEW добавляет 10 минут к задержке; GHOST убирает позывной
     * взломщика из содержимого, даже если тир его обычно раскрывает.
     */
    fun decide(
        ownerFaction: String,
        intruderFaction: String,
        tier: Tier,
        outcome: BreachOutcome,
        matchedEffects: Set<DaemonEffect>,
        now: Long
    ): AlertPlan? {
        if (ownerFaction.isBlank() || ownerFaction == intruderFaction) return null
        if (outcome == BreachOutcome.FAIL && tier == Tier.BASE) return null
        if (DaemonEffect.BLACKOUT in matchedEffects) return null

        val baseDelayMs = if (tier == Tier.NIGHTMARE) 0L else 2 * 60_000L
        val timeskewBonus = if (DaemonEffect.TIMESKEW in matchedEffects) 10 * 60_000L else 0L
        return AlertPlan(
            sendAt = now + baseDelayMs + timeskewBonus,
            revealCallsign = tier != Tier.BASE && DaemonEffect.GHOST !in matchedEffects,
            revealPreciseTime = tier == Tier.NIGHTMARE
        )
    }

    suspend fun dispatch(context: Context, identity: Identity, container: Container, outcome: BreachOutcome, matchedEffects: Set<DaemonEffect>) {
        val now = System.currentTimeMillis()
        val plan = decide(container.ownerFaction, identity.faction, container.tier, outcome, matchedEffects, now)

        ChangeRecordStore.enqueue(
            context, ChangeField.COUNTERS_ALERT, null,
            JSONObject().put("suppressed", plan == null).toString(),
            if (plan == null) ChangeReason.ALERT_SUPPRESSED else ChangeReason.ALERT_SENT,
            sourceRef = container.id, subjectKeyB64 = identity.publicKeyB64,
        )
        if (plan == null) return

        val alert = Mb10Qr.SecurityAlert(
            containerId = container.id,
            containerName = container.name,
            tier = container.tier.level,
            intruderCallsign = if (plan.revealCallsign) identity.callsign else null,
            preciseAt = if (plan.revealPreciseTime) now else null
        )

        Mb10Database.get(context).pendingAlertDao().insert(
            PendingAlertEntity(
                containerId = container.id,
                containerName = container.name,
                faction = container.ownerFaction,
                payload = Mb10QrCodec.encodeSecurityAlert(alert),
                sendAt = plan.sendAt,
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
