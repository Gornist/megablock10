package com.megablok10.app.di

import android.app.Application
import android.content.Context
import com.megablok10.app.BuildConfig
import com.megablok10.app.Mb10App
import com.megablok10.app.PlayerNotices
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.breach.CheckBreachAccess
import com.megablok10.app.breach.ContainerCooldownStore
import com.megablok10.app.breach.DaemonRewards
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.FinishBreach
import com.megablok10.app.breach.SecAlertStore
import com.megablok10.app.breach.SlotClaimStore
import com.megablok10.app.call.CallManager
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.chat.MeshSession
import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.chat.ReceiptConfirmer
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.CollectorClient
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.collector.MasterChangeHooks
import com.megablok10.app.collector.RoomChangeQueue
import com.megablok10.app.collector.SYNC_LOG_TAG
import com.megablok10.app.collector.heartbeat
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.CreateCharacter
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.identity.RamUpgradeStore
import com.megablok10.app.identity.SessionReset
import com.megablok10.app.items.AcceptItem
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.items.SendItem
import com.megablok10.app.log.DeviceDiagnostics
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.net.WireVersion
import com.megablok10.app.presence.MeshLink
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.presence.WifiBinder
import com.megablok10.app.qr.ProvisionStore
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.wallet.AcceptPayment
import com.megablok10.app.wallet.SendPayment
import com.megablok10.app.wallet.TransactionStore
import com.megablok10.kit.net.IncompatibleVersionReporter
import com.megablok10.kit.net.LineSocketClient
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.SyncEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Корень композиции: единственное место, где создаются и связываются друг с другом все долгоживущие части приложения. Остальной
 * код получает зависимости через конструктор и не знает, откуда они взялись, — поэтому любой класс можно собрать в тесте с
 * фейками, а заменить реализацию (другое хранилище, другой транспорт) — правкой здесь, а не по всему коду.
 *
 * Один экземпляр на процесс: создаёт [Mb10App.onCreate], достаётся через `context.appGraph` (Android-компоненты: приёмники,
 * сервисы) и ViewModel-фабрики экранов. Сборка ленивая только там, где это важно для старта процесса; сама конструкция
 * дешёвая — база Room открывается при первом запросе, сеть запускается только [MeshSession.start].
 *
 * Внедрение зависимостей — вручную, без фреймворка: граф небольшой, читается сверху вниз, работает и на JVM-тестах, и в kit.
 */
class AppGraph(private val app: Application) {
    /** Скоуп процесса: фоновые циклы, которые живут, пока жив процесс (синхронизация с коллектором). */
    val processScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val db: Mb10Database = Mb10Database.get(app)
    val notices: PlayerNotices = AppSnack
    val lines = LineSocketClient(Mb10Log)

    // Личность и настройки
    val identity = IdentityStore(prefs(IdentityStore.PREFS))
    val collectorSettings = CollectorSettings(prefs(CollectorSettings.PREFS), defaultUrl = BuildConfig.DEFAULT_COLLECTOR_URL)
    val announcements = AnnouncementStore(prefs(AnnouncementStore.PREFS))
    val contacts = ContactStore(db.characterDao())

    // Записи для мастерского коллектора. Будят синхронизацию, чтобы запись ушла без ожидания следующего опроса.
    private val changeQueue = RoomChangeQueue(db.pendingChangeRecordDao())
    val changes = ChangeRecorder(
        queue = changeQueue,
        signer = identity::recordSigner,
        log = Mb10Log,
        tag = SYNC_LOG_TAG,
        sensitiveFields = setOf(ChangeField.ANNOUNCEMENT),
        onRecorded = { collectorSync.wake() },
    )

    // Сеть на площадке
    val wifi = WifiBinder(app)
    val presence = PresenceService(app, wifi)
    private val peers = { presence.peers.value }
    val outbox = OutboxStore(db.outboxDao(), lines, peers)
    val chat = ChatStore(db.chatMessageDao(), outbox, lines, peers)
    val calls = CallManager(app, peers, db.callLogDao(), lines)
    val directory = ContactDirectory(contacts, presence.peers)

    // Деньги и предметы
    val wallet = TransactionStore(db, identity, changes)
    val shards = ShardStore(db.shardDao(), wallet, changes)
    val daemons = DaemonStore(db.daemonDao(), changes)
    val items = ItemTransferStore(db, identity, shards, daemons)
    val ramUpgrades = RamUpgradeStore(db.consumedTokenDao(), identity, changes)
    val receipts = ReceiptConfirmer(wallet, items)

    // Взлом
    val collectorClient = CollectorClient()
    val cooldowns = ContainerCooldownStore(db.containerBreachDao())
    val slotClaims = SlotClaimStore(db.slotClaimDao(), identity, collectorSettings, collectorClient, peers, lines)
    val secAlerts = SecAlertStore(db.pendingAlertDao(), chat, changes, presence.peers)
    val rewards = DaemonRewards(wallet, shards, daemons, slotClaims, collectorSettings)

    // Сценарии (use cases): потоки из нескольких шагов, одинаковые для интерфейса и стенда e2e (DebugQrReceiver)
    val sendPayment = SendPayment(wallet, chat)
    val acceptPayment = AcceptPayment(wallet, chat)
    val sendItem = SendItem(items, chat)
    val acceptItem = AcceptItem(items, chat)
    val createCharacter = CreateCharacter(identity, changes)
    val checkBreachAccess = CheckBreachAccess({ MeshLink.isOnline(app) }, cooldowns::remainingCooldownMs, slotClaims::isExhausted, changes)
    val finishBreach = FinishBreach(changes, rewards::apply, cooldowns::markRewarded, secAlerts::dispatch)

    // Сессия и жизненный цикл персонажа
    val mesh: MeshSession = MeshSession(
        app, chat, presence, wifi, calls, slotClaims,
        receipts = receipts,
        onIncompatible = IncompatibleVersionReporter(WireVersion.protocols, WireVersion.INCOMPATIBLE_MESSAGE) { notices.show(it) }::report,
        sessionTasks = listOf(
            { scope -> secAlerts.start(scope) },
            { scope -> DeviceDiagnostics.startSnapshots(app, scope, this) },
        ),
    )
    val provisioning = ProvisionStore(identity, collectorSettings, changes, wallet)
    val sessionReset = SessionReset(db, identity, collectorSettings, changes, announcements, mesh)

    /** Фоновый обмен с мастерским коллектором (kit SyncEngine). Запускается один раз — [startCollectorSync]. */
    val collectorSync: SyncEngine by lazy {
        SyncEngine(
            queue = changeQueue,
            transport = collectorClient,
            endpoint = { collectorSettings.baseUrl()?.let { CollectorEndpoint(it, collectorSettings.gameSecret()) } },
            subjectKey = { identity.current?.publicKeyB64 },
            presence = { stats -> heartbeat(app, identity, mesh.listeningPort, stats) },
            hooks = MasterChangeHooks(app, identity, collectorSettings, wallet, announcements, presence, notices),
            log = Mb10Log,
            tag = SYNC_LOG_TAG,
        )
    }

    /** Сведения об устройстве и приложении для архива журнала (`device.txt`). */
    suspend fun deviceReport(): String = DeviceDiagnostics.deviceReport(app, this)

    /** Сколько записей ждёт подтверждения коллектора (Настройки). */
    fun observePendingChanges(): Flow<Int> = changeQueue.observeCount()

    @Volatile private var syncStarted = false

    /** Запускать один раз при старте интерфейса (см. MainActivity). Повторные вызовы — не операция. */
    @Synchronized
    fun startCollectorSync() {
        if (syncStarted) return
        syncStarted = true
        val engine = collectorSync
        processScope.launch { engine.run() }
    }

    private fun prefs(name: String) = app.getSharedPreferences(name, Context.MODE_PRIVATE)
}

/** Граф приложения из любого Context (Activity, сервис, приёмник): процесс всегда создаётся через [Mb10App]. */
val Context.appGraph: AppGraph get() = (applicationContext as Mb10App).graph
