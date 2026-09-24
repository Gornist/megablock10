package com.megablok10.app.collector

import android.content.Context
import com.megablok10.app.PlayerNotices
import com.megablok10.app.announce.AnnouncementNotifier
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.data.CHANGE_SEQ
import com.megablok10.app.data.PendingChangeRecordDao
import com.megablok10.app.data.PendingChangeRecordEntity
import com.megablok10.app.data.SequenceDao
import com.megablok10.app.data.SequenceEntity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.WireVersion
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.wallet.TransactionStore
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.sync.ChangeQueue
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.QueueStats
import com.megablok10.kit.sync.SyncHooks
import kotlinx.coroutines.flow.Flow

/**
 * Синхронизация с мастерским коллектором (§3.4 ТЗ): механика — kit ChangeRecorder (подписать и положить запись в очередь тем же
 * вызовом, что меняет игровые данные, — вызывающий никогда не ждёт сеть) и SyncEngine (фоновая отправка с бэкоффом, правки
 * мастера и их подтверждение); собирает их корень композиции (di.AppGraph). Здесь — части, которые относятся к Мегаблоку.
 * Журнал — под тегом `ChangeRecordStore`, как и раньше.
 */
const val SYNC_LOG_TAG = "ChangeRecordStore"

/**
 * Что телефон сообщает коллектору вместе с heartbeat: порт чата и позывной/фракция (запасное обнаружение), версия приложения и версии
 * построчных протоколов (дашборд подсветит игроков со старой сборкой — им перестанут приходить сообщения, см. net/WireVersion) и
 * очередь неотправленных записей (дашборд увидит телефон «на связи», но с застрявшей синхронизацией). Сервер игнорирует незнакомые
 * поля, поэтому добавление обратно-совместимо. null — нечего сообщать (нет личности или чат-сервер ещё не слушает).
 */
fun heartbeat(app: Context, identity: IdentityStore, chatPort: Int, stats: QueueStats): Map<String, Any?>? {
    val me = identity.current ?: return null
    if (chatPort <= 0) return null
    val appVersion = try { app.packageManager.getPackageInfo(app.packageName, 0).versionName } catch (e: Exception) { null }
    return linkedMapOf(
        "chatPort" to chatPort,
        "callsign" to me.callsign,
        "faction" to me.faction,
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
class MasterChangeHooks(
    private val app: Context,
    private val identity: IdentityStore,
    private val settings: CollectorSettings,
    private val wallet: TransactionStore,
    private val announcements: AnnouncementStore,
    private val presence: PresenceService,
    private val notices: PlayerNotices,
) : SyncHooks {
    override fun onServerPeers(peers: List<PeerInfo>, myPubKeyB64: String) = presence.updateServerPeers(peers, myPubKeyB64)

    override suspend fun onRejected(rejected: Map<String, String>) {
        // Код персонажа не принят: запись не повторяем (иначе синк крутился бы в цикле), но игрок должен узнать и обратиться к мастеру.
        if (ProvisionRejection.anyProvisionError(rejected.values) && !settings.isProvisionRejected()) {
            settings.setProvisionRejected(true)
            Mb10Log.warnEvent(SYNC_LOG_TAG, "provision.rejected_by_server", "reasons" to rejected.values.take(3).joinToString(" | "))
            notices.show(ProvisionRejection.PLAYER_MESSAGE)
        }
    }

    override suspend fun applyMasterChange(change: ChangeRecord) {
        Mb10Log.event(SYNC_LOG_TAG, "master.apply", "id" to change.id, "field" to change.field, "new" to change.newValue.takeIf { change.field != ChangeField.ANNOUNCEMENT }, "reason" to change.reason)
        val newValue = change.newValue ?: return
        when (change.field) {
            ChangeField.BALANCE -> newValue.toLongOrNull()?.let {
                wallet.applyBalanceOverride(change.id, it, change.sourceRef ?: "без основания")
            }
            ChangeField.RAM_CAPACITY -> newValue.toIntOrNull()?.let { identity.applyRamOverride(it) }
            ChangeField.CALLSIGN -> identity.applyCallsignOverride(newValue)
            ChangeField.FACTION -> identity.applyFactionOverride(newValue)
            ChangeField.ANNOUNCEMENT -> if (announcements.add(change.id, newValue)) AnnouncementNotifier.show(app, change.id, newValue)
            else -> Mb10Log.w(SYNC_LOG_TAG, "pending с неизвестным полем ${change.field} — пропущено")
        }
    }
}

/**
 * Таблица Room `pending_change_records` как очередь kit-синхронизации (колонки один в один с ChangeRecord), счётчик seq — в таблице
 * `sequences` той же базы. [legacySeq] — последний номер, выданный прежним счётчиком в SharedPreferences (до версии базы 15): с него
 * нумерация продолжается, чтобы номера, уже ушедшие на сервер, не повторились.
 */
class RoomChangeQueue(
    private val dao: PendingChangeRecordDao,
    private val sequences: SequenceDao,
    private val legacySeq: () -> Long,
) : ChangeQueue {
    /** kit ChangeRecorder зовёт это внутри транзакции вместе с [insert]: номер и запись сохраняются или откатываются вместе. */
    override suspend fun nextSeq(): Long {
        val last = sequences.get(CHANGE_SEQ) ?: maxOf(legacySeq(), dao.maxSeq() ?: 0L)
        return (last + 1).also { sequences.put(SequenceEntity(CHANGE_SEQ, it)) }
    }

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

    /** Сколько записей ждёт подтверждения коллектора — для Настроек. */
    fun observeCount(): Flow<Int> = dao.observeCount()
}
