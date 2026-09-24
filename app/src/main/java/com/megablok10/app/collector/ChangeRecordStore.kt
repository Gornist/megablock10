package com.megablok10.app.collector

import android.content.Context
import com.megablok10.app.announce.AnnouncementNotifier
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.PendingChangeRecordDao
import com.megablok10.app.data.PendingChangeRecordEntity
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.WireVersion
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.wallet.TransactionStore
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.sync.ChangeQueue
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.QueueStats
import com.megablok10.kit.sync.RecordSigner
import com.megablok10.kit.sync.SyncEngine
import com.megablok10.kit.sync.SyncHooks
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

private const val TAG = "ChangeRecordStore"

/**
 * Точка входа для остального приложения: "вот что изменилось, отправь мастерскому коллектору когда сможешь" (§3.4 ТЗ). Механика —
 * kit: [ChangeRecorder] подписывает запись и кладёт в локальную очередь (таблица Room `pending_change_records`) тем же вызовом,
 * что меняет игровые данные, — вызывающий никогда не ждёт сеть; [SyncEngine] в фоне отправляет очередь с бэкоффом, забирает
 * правки мастера и подтверждает их. Здесь — только то, что относится к Мегаблоку: личность, адрес сервера, heartbeat и
 * применение правок мастера (см. [MasterChangeHooks]).
 */
object ChangeRecordStore {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var loopStarted = false
    @Volatile private var sync: Sync? = null

    private class Sync(val recorder: ChangeRecorder, val engine: SyncEngine)

    /** Итог последней попытки синка одной строкой: попадает в снимок состояния. */
    val lastSyncSummary: String get() = sync?.engine?.lastSummary ?: "ещё не было"

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
        sync(context).recorder.record(field, oldValue, newValue, reason, sourceRef, subjectKeyB64, actor)
    }

    /** Запускать один раз при старте приложения (см. MainActivity). Повторные вызовы — не операция. */
    fun start(context: Context) {
        if (loopStarted) return
        loopStarted = true
        val engine = sync(context).engine
        scope.launch { engine.run() }
    }

    private fun sync(context: Context): Sync = sync ?: synchronized(this) {
        sync ?: build(context.applicationContext).also { sync = it }
    }

    private fun build(app: Context): Sync {
        val queue = RoomChangeQueue(Mb10Database.get(app).pendingChangeRecordDao())
        lateinit var engine: SyncEngine
        val recorder = ChangeRecorder(
            queue = queue,
            signer = { IdentityManager.current(app)?.let { IdentitySigner(app, it) } },
            log = Mb10Log,
            tag = TAG,
            sensitiveFields = setOf(ChangeField.ANNOUNCEMENT),
            onRecorded = { engine.wake() },
        )
        engine = SyncEngine(
            queue = queue,
            transport = CollectorClient,
            endpoint = { CollectorSettings.baseUrl(app)?.let { CollectorEndpoint(it, CollectorSettings.gameSecret(app)) } },
            subjectKey = { IdentityManager.current(app)?.publicKeyB64 },
            presence = { stats -> presence(app, stats) },
            hooks = MasterChangeHooks(app),
            log = Mb10Log,
            tag = TAG,
        )
        return Sync(recorder, engine)
    }
}

/** Ключ персонажа как подписант записей: сквозной seq и подпись — в IdentityManager (SharedPreferences устройства). */
private class IdentitySigner(private val app: Context, identity: Identity) : RecordSigner {
    override val publicKeyB64: String = identity.publicKeyB64
    override fun nextSeq(): Long = IdentityManager.nextChangeSeq(app)
    override fun sign(data: ByteArray): String = IdentityManager.sign(app, data)
}

/**
 * Что телефон сообщает коллектору вместе с heartbeat: порт чата и позывной/фракция (запасное обнаружение), версия приложения и версии
 * построчных протоколов (дашборд подсветит игроков со старой сборкой — им перестанут приходить сообщения, см. net/WireVersion) и
 * очередь неотправленных записей (дашборд увидит телефон «на связи», но с застрявшей синхронизацией). Сервер игнорирует незнакомые
 * поля, поэтому добавление обратно-совместимо. null — нечего сообщать (нет личности или чат-сервер ещё не слушает).
 */
private fun presence(app: Context, stats: QueueStats): Map<String, Any?>? {
    val identity = IdentityManager.current(app) ?: return null
    val port = ChatStore.listeningPort
    if (port <= 0) return null
    val appVersion = try { app.packageManager.getPackageInfo(app.packageName, 0).versionName } catch (e: Exception) { null }
    return linkedMapOf(
        "chatPort" to port,
        "callsign" to identity.callsign,
        "faction" to identity.faction,
        "appVersion" to (appVersion ?: "unknown"),
        "wireVersions" to WireVersion.REPORTED,
        "pendingCount" to stats.pendingCount,
        "oldestPendingAgeMs" to stats.oldestPendingAgeMs,
    )
}

/**
 * Реакция Мегаблока на ответ коллектора: подсказки адресов других игроков, отказ по коду персонажа и правки мастера (§6.3, §6.5
 * ТЗ — правка видна в истории наравне с игровыми, но это забота сервера: он её уже записал). Каждый сеттер правки — "тихий", без
 * обратной записи на сервер (см. applyRamOverride/applyBalanceOverride), иначе получили бы эхо в историю. Неизвестное поле —
 * пропускаем, не роняя остальные правки в пачке; сбой на конкретной правке движок логирует и всё равно подтверждает.
 */
private class MasterChangeHooks(private val app: Context) : SyncHooks {
    override fun onServerPeers(peers: List<PeerInfo>, myPubKeyB64: String) = PresenceService.updateServerPeers(peers, myPubKeyB64)

    override suspend fun onRejected(rejected: Map<String, String>) {
        // Код персонажа не принят: запись не повторяем (иначе синк крутился бы в цикле), но игрок должен узнать и обратиться к мастеру.
        if (ProvisionRejection.anyProvisionError(rejected.values) && !CollectorSettings.isProvisionRejected(app)) {
            CollectorSettings.setProvisionRejected(app, true)
            Mb10Log.warnEvent(TAG, "provision.rejected_by_server", "reasons" to rejected.values.take(3).joinToString(" | "))
            AppSnack.show(ProvisionRejection.PLAYER_MESSAGE)
        }
    }

    override suspend fun applyMasterChange(change: ChangeRecord) {
        Mb10Log.event(TAG, "master.apply", "id" to change.id, "field" to change.field, "new" to change.newValue.takeIf { change.field != ChangeField.ANNOUNCEMENT }, "reason" to change.reason)
        val newValue = change.newValue ?: return
        when (change.field) {
            ChangeField.BALANCE -> newValue.toLongOrNull()?.let {
                TransactionStore.applyBalanceOverride(app, change.id, it, change.sourceRef ?: "без основания")
            }
            ChangeField.RAM_CAPACITY -> newValue.toIntOrNull()?.let { IdentityManager.applyRamOverride(app, it) }
            ChangeField.CALLSIGN -> IdentityManager.applyCallsignOverride(app, newValue)
            ChangeField.FACTION -> IdentityManager.applyFactionOverride(app, newValue)
            ChangeField.ANNOUNCEMENT -> if (AnnouncementStore.add(app, change.id, newValue)) AnnouncementNotifier.show(app, change.id, newValue)
            else -> Mb10Log.w(TAG, "pending с неизвестным полем ${change.field} — пропущено")
        }
    }
}

/** Таблица Room `pending_change_records` как очередь kit-синхронизации (колонки один в один с ChangeRecord, миграция не нужна). */
internal class RoomChangeQueue(private val dao: PendingChangeRecordDao) : ChangeQueue {
    override suspend fun insert(record: ChangeRecord) = dao.insert(
        PendingChangeRecordEntity(
            id = record.id, subjectKeyB64 = record.subjectKeyB64, seq = record.seq, happenedAt = record.happenedAt,
            field = record.field, oldValue = record.oldValue, newValue = record.newValue, reason = record.reason,
            sourceRef = record.sourceRef, actor = record.actor, signature = record.signature,
        ),
    )

    override suspend fun nextBatch(limit: Int): List<ChangeRecord> = dao.nextBatch(limit).map {
        ChangeRecord(it.id, it.subjectKeyB64, it.seq, it.happenedAt, it.field, it.oldValue, it.newValue, it.reason, it.sourceRef, it.actor, it.signature)
    }

    override suspend fun deleteByIds(ids: List<String>) = dao.deleteByIds(ids)
    override suspend fun count(): Int = dao.count()
    override suspend fun oldestHappenedAt(): Long? = dao.oldestHappenedAt()
}
