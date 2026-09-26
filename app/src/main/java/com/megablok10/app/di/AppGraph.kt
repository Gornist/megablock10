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
import com.megablok10.app.chat.CardResender
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.chat.MeshSession
import com.megablok10.app.chat.OutboxStore
import com.megablok10.app.chat.ReadReceiptSetting
import com.megablok10.app.chat.ReadReceipts
import com.megablok10.app.chat.ReceiptConfirmer
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.CollectorClient
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.collector.MasterChangeHooks
import com.megablok10.app.collector.RoomChangeQueue
import com.megablok10.app.collector.SYNC_LOG_TAG
import com.megablok10.app.collector.heartbeat
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.RoomTransactor
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.CreateCharacter
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.identity.RamUpgradeStore
import com.megablok10.app.identity.SessionReset
import com.megablok10.app.items.AcceptItem
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.items.SendItem
import com.megablok10.app.log.DeviceDiagnostics
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.presence.MeshForegroundService
import com.megablok10.app.session.SessionActions
import com.megablok10.app.session.SessionController
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
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.net.LineSocketClient
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.SyncEngine
import com.megablok10.kit.sync.Transactor
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
    /** Все транзакции базы — через него: изменение данных и запись о нём для мастера фиксируются одним коммитом. */
    val transactor: Transactor = RoomTransactor(db)
    val notices: PlayerNotices = AppSnack
    // Исход каждой отправки — таблице пиров: рабочий адрес игрока первым, отказавший — в конец (kit PeerTable, B2).
    val lines = LineSocketClient(Mb10Log) { host, port, outcome, answeredBy -> presence.reportSend(host, port, outcome, answeredBy) }

    // Личность и настройки
    val identity = IdentityStore(prefs(IdentityStore.PREFS))
    val collectorSettings = CollectorSettings(prefs(CollectorSettings.PREFS), defaultUrl = BuildConfig.DEFAULT_COLLECTOR_URL)
    val announcements = AnnouncementStore(prefs(AnnouncementStore.PREFS))
    val contacts = ContactStore(db.characterDao())

    // Записи для мастерского коллектора. Будят синхронизацию, чтобы запись ушла без ожидания следующего опроса.
    private val changeQueue = RoomChangeQueue(db.pendingChangeRecordDao(), db.sequenceDao(), identity::legacyChangeSeq, db.acceptedChangeRecordDao(), transactor)
    val changes = ChangeRecorder(
        queue = changeQueue,
        signer = identity::recordSigner,
        log = Mb10Log,
        tag = SYNC_LOG_TAG,
        sensitiveFields = setOf(ChangeField.ANNOUNCEMENT),
        onRecorded = { collectorSync.wake() },
        transactor = transactor,
    )

    // Сеть на площадке
    val wifi = WifiBinder(app)
    val presence = PresenceService(app, wifi)
    /** Одно место адресации пиров (B1): снаружи — игроки и «отправь игроку», адреса и их перебор — внутри (kit PeerDirectory). */
    val peerDirectory = PeerDirectory(
        addresses = { presence.peers.value },
        online = presence.players,
        me = { identity.current?.let { it.publicKeyB64 to mesh.listeningPort } },
    ) { host, port, line, expect -> lines.sendLineOutcome(host, port, line, expectAckFrom = expect) }
    val outbox: OutboxStore = OutboxStore(db.outboxDao(), peerDirectory) { line -> chat.markDelivered(line) }
    val chat: ChatStore = ChatStore(db.chatMessageDao(), outbox, peerDirectory)
    val calls = CallManager(app, peerDirectory, db.callLogDao())
    /** Отчёты о прочтении (D4) и переключатель «как в мессенджерах». */
    val readReceiptSetting = ReadReceiptSetting(prefs(ReadReceiptSetting.PREFS))
    val readReceipts = ReadReceipts(db.chatMessageDao(), peerDirectory, outbox, readReceiptSetting)
    val directory = ContactDirectory(contacts, peerDirectory.online)

    // Деньги и предметы
    val wallet = TransactionStore(db, identity, changes, transactor)
    val shards = ShardStore(db.shardDao(), wallet, changes, transactor)
    val daemons = DaemonStore(db.daemonDao(), changes, transactor)
    val items = ItemTransferStore(db, identity, shards, daemons, transactor)
    val ramUpgrades = RamUpgradeStore(db.consumedTokenDao(), identity, changes, transactor)
    val receipts = ReceiptConfirmer(wallet, items)
    /** Карточки, доставленные, но без чека получателя, — снова адресату, когда он виден (фоновая задача сетевой сессии). */
    val cardResender = CardResender(
        stuck = { before -> wallet.deliveredUnconfirmed(before) + items.deliveredUnconfirmed(before) },
        originalMessage = chat::outgoingCard,
        send = chat::resend,
        online = peerDirectory::isOnline,
        me = { identity.current?.publicKeyB64 },
    )

    // Взлом
    val collectorClient = CollectorClient()
    val cooldowns = ContainerCooldownStore(db.containerBreachDao())
    val slotClaims = SlotClaimStore(db.slotClaimDao(), identity, collectorSettings, collectorClient, peerDirectory)
    val secAlerts = SecAlertStore(db.pendingAlertDao(), chat, changes, peerDirectory.online)
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
        readReceipts = readReceipts,
        onIncompatible = IncompatibleVersionReporter(WireVersion.protocols, WireVersion.INCOMPATIBLE_MESSAGE) { notices.show(it) }::report,
        sessionTasks = listOf(
            { scope -> secAlerts.start(scope) },
            { scope -> cardResender.start(scope) },
            { scope -> DeviceDiagnostics.startSnapshots(app, scope, this) },
        ),
    )
    val provisioning = ProvisionStore(identity, collectorSettings, changes, wallet, db.consumedTokenDao(), transactor)
    val sessionReset = SessionReset(db, identity, collectorSettings, changes, announcements) { session.onSessionReset() }

    /**
     * Что работает в фоне — решает только он (B3): сеть на личность, синк на процесс, foreground-сервис с правилами Android 12+.
     * Адаптер ниже — единственное место, где зовутся mesh.start/stop, запуск синка и MeshForegroundService (SessionGuardTest).
     */
    val session: SessionController = SessionController(object : SessionActions {
        override fun startMesh(identity: Identity) = mesh.start(identity)
        override fun stopMesh() = mesh.stop()
        override fun startSync() { val engine = collectorSync; processScope.launch { engine.run() } }
        override fun startForeground(): Boolean = MeshForegroundService.start(app)
        override fun stopForeground() = MeshForegroundService.stop(app)
    })

    /** Фоновый обмен с мастерским коллектором (kit SyncEngine). Запускается один раз — SessionController (startSync). */
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


    /**
     * Доделать операции, прерванные падением прошлого процесса посередине: выдачу персонажа по QR и RAM-апгрейд (см.
     * ProvisionStore, RamUpgradeStore). Зовётся один раз при запуске процесса ([Mb10App.onCreate]).
     */
    fun resumeInterruptedWork() {
        processScope.launch {
            runCatching { provisioning.resumeInterrupted() }.onFailure { Mb10Log.e("App", "не удалось доделать выдачу: ${it.message}", it) }
            runCatching { ramUpgrades.resumeInterrupted() }.onFailure { Mb10Log.e("App", "не удалось доделать RAM-апгрейд: ${it.message}", it) }
        }
    }

    /**
     * Запуск процесса ([Mb10App.onCreate]): синк сразу, сеть — при появлении личности. Подписка живёт в [processScope] с момента
     * старта, поэтому работает и когда система поднимает процесс сама (MeshForegroundService — START_STICKY) без единой Activity.
     */
    fun startSession() {
        session.onProcessStarted()
        processScope.launch { identity.state.collect { session.onIdentity(it) } }
    }

    private fun prefs(name: String) = app.getSharedPreferences(name, Context.MODE_PRIVATE)
}

/** Граф приложения из любого Context (Activity, сервис, приёмник): процесс всегда создаётся через [Mb10App]. */
val Context.appGraph: AppGraph get() = (applicationContext as Mb10App).graph
