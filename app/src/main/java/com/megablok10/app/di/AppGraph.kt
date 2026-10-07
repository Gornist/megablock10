package com.megablok10.app.di

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.megablok10.app.BuildConfig
import com.megablok10.app.Mb10App
import com.megablok10.app.PlayerNotices
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.breach.BreachHintStore
import com.megablok10.app.breach.CheckBreachAccess
import com.megablok10.app.breach.ContainerCooldownStore
import com.megablok10.app.breach.DaemonRewards
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.FinishBreach
import com.megablok10.app.breach.SecAlertStore
import com.megablok10.app.breach.SlotClaimStore
import com.megablok10.app.call.AndroidProximityScreenLock
import com.megablok10.app.call.CallManager
import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallProximityGuard
import com.megablok10.app.call.IncomingCallNotifier
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
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.data.RoomTransactor
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.headset.ChatStoreHeadsetPort
import com.megablok10.app.headset.HeadsetCallBridge
import com.megablok10.app.headset.CallVoiceAudio
import com.megablok10.app.headset.HeadsetMirror
import com.megablok10.app.headset.HeadsetVoiceBridge
import com.megablok10.app.headset.HeadsetRuntime
import com.megablok10.app.headset.HeadsetSettings
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
import com.megablok10.app.log.LogStore
import com.megablok10.app.log.Mb10Log
import com.megablok10.app.log.Mb10LogStore
import com.megablok10.app.netrun.NetrunEntry
import com.megablok10.app.netrun.NetrunStore
import com.megablok10.app.netrun.WorldAutoAccept
import com.megablok10.app.presence.MeshForegroundService
import com.megablok10.app.session.SessionActions
import com.megablok10.app.session.SessionController
import com.megablok10.app.sound.SoundPlayer
import com.megablok10.app.ui.nav.ShellBadges
import com.megablok10.app.net.WireVersion
import com.megablok10.app.presence.MeshLink
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.presence.WifiBinder
import com.megablok10.app.qr.ProvisionStore
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.voice.AndroidClipPlayer
import com.megablok10.app.voice.VoiceAutoplaySetting
import com.megablok10.app.voice.VoiceMessenger
import com.megablok10.app.voice.VoicePlayer
import com.megablok10.app.voice.VoiceStore
import com.megablok10.app.voice.voiceTrack
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
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
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
    val netrunStore = NetrunStore(prefs(NetrunStore.PREFS))

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
    /** Файлы голосовых сообщений (voice.VoiceStore): стираются сбросом персонажа. */
    val voiceStore = VoiceStore(java.io.File(app.filesDir, "voice"))
    val outbox: OutboxStore = OutboxStore(db.outboxDao(), peerDirectory, expand = { VoiceMessenger.expand(it, voiceStore) }) { line -> chat.markDelivered(line) }
    val chat: ChatStore = ChatStore(db.chatMessageDao(), outbox, peerDirectory)
    val voice = VoiceMessenger(db.chatMessageDao(), outbox, peerDirectory, voiceStore)
    val calls = CallManager(app, peerDirectory, db.callLogDao())
    val voiceAutoplay = VoiceAutoplaySetting(prefs(VoiceAutoplaySetting.PREFS))
    /** Проигрыватель голосовых: один на приложение, на главном потоке (MediaPlayer), выход из треда его не обрывает; звонок останавливает ([sessionTasks]). */
    val voicePlayer = VoicePlayer(
        engine = AndroidClipPlayer(app),
        store = voiceStore,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        markListened = { db.chatMessageDao().raiseStatus(it, MessageStatus.LISTENED) },
        nextUnlistened = { peer, after -> identity.current?.let { me -> db.chatMessageDao().nextUnlistenedVoice(me.publicKeyB64, peer, after)?.voiceTrack(me.publicKeyB64) } },
        autoplay = { voiceAutoplay.enabled.value },
    )
    val logStore: LogStore = Mb10LogStore(app)
    /** Отчёты о прочтении (D4) и переключатель «как в мессенджерах». */
    val readReceiptSetting = ReadReceiptSetting(prefs(ReadReceiptSetting.PREFS))
    val readReceipts = ReadReceipts(db.chatMessageDao(), peerDirectory, outbox, readReceiptSetting)
    /** Игроки в сети для экранов и рассылок: без Моста «Сети» (он в PeerDirectory ради отправки, но не игрок). */
    val visiblePlayers: StateFlow<List<OnlinePlayer>> = peerDirectory.online
        .map { list -> list.filter { it.pubKeyB64 != netrunStore.worldPub() } }
        .stateIn(processScope, SharingStarted.Eagerly, emptyList())
    val directory = ContactDirectory(contacts, visiblePlayers)
    /** Бейджи меню новой оболочки (docs/ux/ui-migration-plan.md, «Нужны данные» перед M3) — локальный водяной знак, не read-receipt. */
    val shellBadges = ShellBadges(db.chatMessageDao(), db.callLogDao(), prefs(ShellBadges.PREFS))

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
    val breachHint = BreachHintStore(prefs(BreachHintStore.PREFS))
    val slotClaims = SlotClaimStore(db.slotClaimDao(), identity, collectorSettings, collectorClient, peerDirectory)
    val secAlerts = SecAlertStore(db.pendingAlertDao(), chat, changes, visiblePlayers)
    val rewards = DaemonRewards(wallet, shards, daemons, slotClaims, collectorSettings)

    // Сценарии (use cases): потоки из нескольких шагов, одинаковые для интерфейса и стенда e2e (DebugQrReceiver)
    val sendPayment = SendPayment(wallet, chat)
    val acceptPayment = AcceptPayment(wallet, chat)
    val sendItem = SendItem(items, chat)
    val acceptItem = AcceptItem(items, chat)
    val createCharacter = CreateCharacter(identity, changes)
    val checkBreachAccess = CheckBreachAccess({ MeshLink.isOnline(app) }, cooldowns::remainingCooldownMs, slotClaims::isExhausted, changes)
    val finishBreach = FinishBreach(changes, rewards::apply, cooldowns::markRewarded, secAlerts::dispatch)

    // «Сеть»: вход со стойки (карточки демонов + запрос Мосту) и автоприём добычи от Моста
    val netrun = NetrunEntry(
        store = netrunStore, ledger = items, messenger = chat,
        sendLine = { key, line -> peerDirectory.send(key, line) },
        addPeer = presence::addStaticPeer,
        sign = identity::sign,
        work = processScope,
    )
    val worldCards = WorldAutoAccept(netrunStore::worldPub, items, wallet, chat, processScope, onWorldCard = netrun::onWorldCard)

    // Очки Pico как второй экран (docs/netrun-phone-link.md): за переключателем в «Сеть» → «Очки», по умолчанию выключено. Запускается задачей сессии ниже.
    val headsetSettings = HeadsetSettings(prefs(HeadsetSettings.PREFS))
    val headset = HeadsetRuntime(app, headsetSettings) { onReady ->
        HeadsetMirror(
            ChatStoreHeadsetPort(db.chatMirrorDao(), chat, contacts), { identity.current }, headsetSettings, onReady,
            callBridge = HeadsetCallBridge(
                calls, { visiblePlayers.value },
                micGranted = { ContextCompat.checkSelfPermission(app, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED },
            ),
            voiceBridge = HeadsetVoiceBridge(calls, CallVoiceAudio(), { headsetSettings.config.value.let { it.enabled && it.voiceEnabled } }),
        )
    }.also { SoundPlayer.mirror = it }

    // Сессия и жизненный цикл персонажа
    val mesh: MeshSession = MeshSession(
        app, chat, presence, wifi, calls, slotClaims,
        receipts = receipts,
        readReceipts = readReceipts,
        voice = voice,
        netrun = netrun,
        worldCards = worldCards,
        onIncompatible = IncompatibleVersionReporter(WireVersion.protocols, WireVersion.INCOMPATIBLE_MESSAGE) { notices.show(it) }::report,
        sessionTasks = listOf(
            { scope -> secAlerts.start(scope) },
            { scope -> cardResender.start(scope) },
            { scope -> headset.start(scope) },
            { scope -> IncomingCallNotifier(app, calls).start(scope) },
            { _ -> voicePlayer.stopDuring(calls.state.map { it.phase != CallPhase.IDLE }) },
            { scope -> CallProximityGuard(calls, AndroidProximityScreenLock(app)).start(scope) },
            { _ -> netrun.restorePeer() },
            { scope -> DeviceDiagnostics.startSnapshots(app, scope, diagnosticsState) },
        ),
    )
    val provisioning = ProvisionStore(identity, collectorSettings, changes, wallet, db.consumedTokenDao(), transactor)
    val sessionReset = SessionReset(db, transactor, identity, collectorSettings, changes, announcements, netrun, voiceStore) { voicePlayer.requestStop(); session.onSessionReset() }

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

    /** Срез состояния для снимков и device.txt (DeviceDiagnostics); sync читается лениво, как раньше. */
    private val diagnosticsState = object : DeviceDiagnostics.AppState {
        override val identity: Identity? get() = this@AppGraph.identity.current
        override suspend fun outboxPending(): Int = outbox.pending()
        override val wifiBound: Boolean get() = wifi.boundNetwork != null
        override val ownIpv4: String? get() = wifi.ownIpv4
        override val chatPort: Int get() = mesh.listeningPort
        override fun describePeers(): String = presence.describePeers()
        override val syncSummary: String get() = collectorSync.lastSummary
    }

    /** Сведения об устройстве и приложении для архива журнала (`device.txt`). */
    suspend fun deviceReport(): String = DeviceDiagnostics.deviceReport(app, diagnosticsState)

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
