package com.megablok10.app.collector

import android.content.Context
import android.util.Log
import com.megablok10.app.announce.AnnouncementNotifier
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.PendingChangeRecordEntity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.net.WireVersion
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.util.UUID

private const val TAG = "ChangeRecordStore"
private const val BATCH_SIZE = 200
private val BACKOFF_STEPS_MS = longArrayOf(1_000, 2_000, 5_000, 15_000, 60_000)

/**
 * Точка входа для остального приложения: "вот что изменилось, отправь
 * мастерскому коллектору когда сможешь" (§3.4 ТЗ). Пишет в локальную
 * очередь синхронно с игровым действием (тем же вызовом, что меняет Room-
 * сущность), саму отправку делает фоновый цикл с бэкоффом — вызывающая
 * сторона никогда не ждёт сеть.
 */
object ChangeRecordStore {
    private val wake = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var loopStarted = false

    /** actor по умолчанию — сам subject; для TRANSFER_IN вызывающая сторона передаёт actor = ключ контрагента (§3.1 исключение). */
    suspend fun enqueue(
        context: Context,
        field: String,
        oldValue: String?,
        newValue: String,
        reason: String,
        sourceRef: String? = null,
        subjectKeyB64: String? = null,
        actor: String? = null,
    ) {
        val identity = IdentityManager.current(context) ?: run {
            Log.w(TAG, "нет личности устройства — запись $field/$reason потеряна")
            return
        }
        val subject = subjectKeyB64 ?: identity.publicKeyB64
        val seq = IdentityManager.nextChangeSeq(context)
        val record = ChangeRecord(
            id = UUID.randomUUID().toString(),
            subjectKeyB64 = subject,
            seq = seq,
            happenedAt = System.currentTimeMillis(),
            field = field,
            oldValue = oldValue,
            newValue = newValue,
            reason = reason,
            sourceRef = sourceRef,
            actor = actor ?: identity.publicKeyB64,
            signature = "",
        )
        val signed = record.copy(signature = IdentityManager.sign(context, record.signaturePayload()))

        Mb10Database.get(context).pendingChangeRecordDao().insert(
            PendingChangeRecordEntity(
                id = signed.id, subjectKeyB64 = signed.subjectKeyB64, seq = signed.seq, happenedAt = signed.happenedAt,
                field = signed.field, oldValue = signed.oldValue, newValue = signed.newValue, reason = signed.reason,
                sourceRef = signed.sourceRef, actor = signed.actor, signature = signed.signature,
            ),
        )
        wake.tryEmit(Unit)
    }

    /** Запускать один раз при старте приложения (см. MainActivity). Повторные вызовы — не операция. */
    fun start(context: Context) {
        if (loopStarted) return
        loopStarted = true
        val appContext = context.applicationContext
        scope.launch { syncLoop(appContext) }
    }

    /**
     * Опрашивает коллектор ДАЖЕ когда исходящая очередь пуста — единственный
     * способ узнать про новую правку мастера (§6.3): push-канала нет,
     * коллектор отдаёт pending тем же ответом на POST /api/changes, но
     * только если его спросить. Пустой батч с subjectKeyB64 — легитимный
     * запрос именно за этим, не только досылка исходящего.
     */
    private suspend fun syncLoop(context: Context) {
        var backoffIndex = 0
        // id применённых правок мастера, о которых коллектор ещё не знает: уходят в следующем запросе,
        // и только после этого он перестаёт присылать их заново.
        var pendingAcks: List<String> = emptyList()
        while (true) {
            try {
                val step = syncOnce(context, pendingAcks, backoffIndex)
                pendingAcks = step.acks
                backoffIndex = step.backoffIndex
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Любой сбой одной итерации (Room, разбор ответа, применение правки) не должен
                // навсегда останавливать синк — идём на бэкофф и пробуем снова.
                Log.w(TAG, "итерация синка упала: ${e.message}", e)
                val delayMs = BACKOFF_STEPS_MS[backoffIndex.coerceAtMost(BACKOFF_STEPS_MS.lastIndex)]
                backoffIndex++
                waitForWakeOrTimeout(delayMs)
            }
        }
    }

    private class SyncStep(val acks: List<String>, val backoffIndex: Int)

    /** Одна итерация цикла синка. Возвращает актуальные ack-и и индекс бэкоффа; исключения — на вызывающей стороне (syncLoop). */
    private suspend fun syncOnce(context: Context, acksIn: List<String>, backoffIn: Int): SyncStep {
        val baseUrl = CollectorSettings.baseUrl(context)
        if (baseUrl == null) {
            waitForWakeOrTimeout(30_000)
            return SyncStep(acksIn, 0)
        }

        val dao = Mb10Database.get(context).pendingChangeRecordDao()
        val batch = dao.nextBatch(BATCH_SIZE)
        val identity = IdentityManager.current(context)
        val records = batch.map {
            ChangeRecord(it.id, it.subjectKeyB64, it.seq, it.happenedAt, it.field, it.oldValue, it.newValue, it.reason, it.sourceRef, it.actor, it.signature)
        }
        val port = ChatStore.listeningPort
        // Очередь неотправленных записей — в heartbeat: дашборд увидит телефон «на связи», но с застрявшей синхронизацией.
        val pendingCount = dao.count()
        val oldestPendingAgeMs = dao.oldestHappenedAt()?.let { (System.currentTimeMillis() - it).coerceAtLeast(0) } ?: 0L
        val presence = if (identity != null && port > 0) presenceJson(context, port, identity.callsign, identity.faction, pendingCount, oldestPendingAgeMs) else null
        val result = CollectorClient.sendBatch(baseUrl, records, identity?.publicKeyB64, CollectorSettings.gameSecret(context), acksIn, presence)

        if (result == null) {
            // Сеть/коллектор недоступны — экспоненциальный бэкофф (§3.4: 1с → 2с → 5с → 15с → 60с, дальше по минуте).
            val delayMs = BACKOFF_STEPS_MS[backoffIn.coerceAtMost(BACKOFF_STEPS_MS.lastIndex)]
            waitForWakeOrTimeout(delayMs)
            return SyncStep(acksIn, backoffIn + 1)
        }

        if (identity != null) PresenceService.updateServerPeers(result.peers, identity.publicKeyB64)

        val toDelete = result.accepted + result.rejected.keys
        if (toDelete.isNotEmpty()) dao.deleteByIds(toDelete.toList())
        if (result.rejected.isNotEmpty()) {
            Log.w(TAG, "коллектор отбраковал ${result.rejected.size} записей: ${result.rejected.values.take(3)}")
            // Код персонажа не принят: запись не повторяем (иначе синк крутился бы в цикле), но игрок должен узнать и обратиться к мастеру.
            if (ProvisionRejection.anyProvisionError(result.rejected.values) && !CollectorSettings.isProvisionRejected(context)) {
                CollectorSettings.setProvisionRejected(context, true)
                AppSnack.show(ProvisionRejection.PLAYER_MESSAGE)
            }
        }
        // Запрос с acksIn дошёл — коллектор их учёл; новые ack-и — по правкам, применённым прямо сейчас.
        val newAcks = if (result.pending.isNotEmpty()) applyPending(context, result.pending) else emptyList()

        if (batch.isEmpty() && result.pending.isEmpty()) {
            // Действительно нечего ни слать, ни получать — обычный простой, не долбим коллектор чаще раза в 30с.
            waitForWakeOrTimeout(30_000)
        }
        // Иначе сразу на новый виток: либо не всё отправили (MAX_BATCH), либо только что применили pending
        // и надо отправить ack и проверить очередь ещё раз без задержки.
        return SyncStep(newAcks, 0)
    }

    /**
     * Применяет MASTER_OVERRIDE с дашборда локально (§6.3, §6.5 ТЗ — правка
     * видна в истории наравне с игровыми, но это забота сервера: он её уже
     * записал). Каждый сеттер здесь — "тихий", без обратной эмиссии
     * ChangeRecord (см. applyRamOverride/applyBalanceOverride) — иначе
     * получили бы эхо в историю. Неизвестное поле — просто пропускаем,
     * не роняя остальные записи в пачке. Возвращает id обработанных правок
     * для ack: одна "ядовитая" правка не должна доставляться вечно, поэтому
     * сбой на конкретной записи логируется, а id всё равно подтверждается.
     */
    private suspend fun applyPending(context: Context, pending: List<ChangeRecord>): List<String> {
        for (p in pending) {
            try {
                val newValue = p.newValue ?: continue
                when (p.field) {
                    ChangeField.BALANCE -> newValue.toLongOrNull()?.let {
                        TransactionStore.applyBalanceOverride(context, p.id, it, p.sourceRef ?: "без основания")
                    }
                    ChangeField.RAM_CAPACITY -> newValue.toIntOrNull()?.let { IdentityManager.applyRamOverride(context, it) }
                    ChangeField.CALLSIGN -> IdentityManager.applyCallsignOverride(context, newValue)
                    ChangeField.FACTION -> IdentityManager.applyFactionOverride(context, newValue)
                    ChangeField.ANNOUNCEMENT -> if (AnnouncementStore.add(context, p.id, newValue)) AnnouncementNotifier.show(context, p.id, newValue)
                    else -> Log.w(TAG, "pending с неизвестным полем ${p.field} — пропущено")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "не удалось применить правку ${p.id}: ${e.message}", e)
            }
        }
        return pending.map { it.id }
    }

    private suspend fun waitForWakeOrTimeout(timeoutMs: Long) {
        kotlinx.coroutines.withTimeoutOrNull(timeoutMs) { wake.first() }
    }
}

/**
 * Что телефон сообщает коллектору вместе с heartbeat: порт чата и позывной/фракция (запасное обнаружение), версия приложения и версии
 * построчных протоколов (дашборд подсветит игроков со старой сборкой — им перестанут приходить сообщения, см. net/WireVersion).
 * Сервер игнорирует незнакомые поля, поэтому добавление обратно-совместимо.
 */
private fun presenceJson(context: Context, chatPort: Int, callsign: String, faction: String, pendingCount: Int, oldestPendingAgeMs: Long): JSONObject {
    val appVersion = try { context.packageManager.getPackageInfo(context.packageName, 0).versionName } catch (e: Exception) { null }
    val wire = JSONObject().also { o -> WireVersion.REPORTED.forEach { (k, v) -> o.put(k, v) } }
    return JSONObject().put("chatPort", chatPort).put("callsign", callsign).put("faction", faction)
        .put("appVersion", appVersion ?: "unknown").put("wireVersions", wire)
        .put("pendingCount", pendingCount).put("oldestPendingAgeMs", oldestPendingAgeMs)
}
