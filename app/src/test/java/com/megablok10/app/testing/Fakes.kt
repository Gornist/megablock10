package com.megablok10.app.testing

import android.content.SharedPreferences
import com.megablok10.app.PlayerNotices
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonCollection
import com.megablok10.app.call.CallControls
import com.megablok10.app.call.CallUiState
import com.megablok10.app.chat.ChatInbox
import com.megablok10.app.chat.DirectMessenger
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CharacterDao
import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.ItemTransferEntity
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.items.ItemLedger
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.shards.ShardCollection
import com.megablok10.app.wallet.PaymentLedger
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.handover.Handover
import com.megablok10.kit.handover.HandoverRules
import com.megablok10.kit.handover.OutgoingJournal
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.SendOutcome
import com.megablok10.kit.sync.ChangeQueue
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.RecordSigner
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import java.security.KeyPair

/** Игрок для тестов: настоящая пара ключей, подписи проверяются теми же функциями, что в приложении. */
class TestPlayer(val callsign: String, val faction: String = "Малстром") {
    val keys: KeyPair = Ecdsa.generateKeyPair()
    val key: String = Ecdsa.encodeKey(keys.public)
    val identity = Identity(key, callsign, faction)
    val peer = OnlinePlayer(key, callsign, faction)

    fun sign(data: ByteArray): String = Ecdsa.sign(keys.private, data)
    fun sign(data: String): String = sign(data.toByteArray(Charsets.UTF_8))
}

/** Записи для мастера в памяти: настоящий kit ChangeRecorder с подписью ключом [player]. */
class RecordedChanges(player: TestPlayer?) : ChangeQueue {
    val rows = mutableListOf<ChangeRecord>()
    private var seq = 0L
    private val signer = player?.let {
        object : RecordSigner {
            override val publicKeyB64 = it.key
            override fun sign(data: ByteArray) = it.sign(data)
        }
    }
    val recorder = ChangeRecorder(this, { signer })

    override suspend fun nextSeq() = ++seq
    override suspend fun lastSeq() = seq
    override suspend fun insert(record: ChangeRecord) { rows += record }
    override suspend fun nextBatch(limit: Int) = rows.take(limit)
    override suspend fun deleteByIds(ids: List<String>) { rows.removeAll { it.id in ids } }
    override suspend fun count() = rows.size
    override suspend fun oldestHappenedAt() = rows.minOfOrNull { it.happenedAt }
}

/** Отправленное личное сообщение: кому, был ли адресат виден (null — нет) и что. */
data class SentDirect(val to: String, val peer: OnlinePlayer?, val body: String)

/** Личка в памяти: кто «в сети» — [online], исход отправки видимому адресату — [outcome]. */
class FakeMessenger(vararg online: OnlinePlayer) : DirectMessenger {
    val online = online.toMutableList()
    var outcome = SendOutcome.DELIVERED
    val sent = mutableListOf<SentDirect>()

    /** Что знал журнал в момент отправки — чтобы проверять порядок «DELIVERED до отправки». */
    var onSend: () -> Unit = {}

    override fun onlinePeer(pubKeyB64: String) = online.find { it.pubKeyB64 == pubKeyB64 }

    override suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, peer: OnlinePlayer?, body: String) =
        sendDirectOutcome(identity, peerPubKeyB64, peer, body) == SendOutcome.DELIVERED

    override suspend fun sendDirectOutcome(identity: Identity, peerPubKeyB64: String, peer: OnlinePlayer?, body: String): SendOutcome {
        onSend()
        sent += SentDirect(peerPubKeyB64, peer, body)
        return if (peer == null) SendOutcome.NOT_REACHED else outcome
    }
}

/** Статусы исходящих в памяти — журнал kit Handover с теми же переходами, что условия в SQL-запросах DAO. */
class MemoryJournal(private val status: MutableMap<String, String>, private val recipient: (String) -> String?) : OutgoingJournal {
    override suspend fun markDelivered(id: String) = transition(id, setOf(TransactionStatus.PENDING), TransactionStatus.DELIVERED)
    override suspend fun markUndelivered(id: String) = transition(id, setOf(TransactionStatus.DELIVERED), TransactionStatus.PENDING)
    override suspend fun confirm(id: String) = transition(id, setOf(TransactionStatus.PENDING, TransactionStatus.DELIVERED), TransactionStatus.CONFIRMED)
    override suspend fun recipientOf(id: String): String? = recipient(id)

    /** Как UPDATE … WHERE status IN (…): число изменённых строк. */
    private fun transition(id: String, from: Set<String>, to: String): Int {
        if (status[id] !in from) return 0
        status[id] = to
        return 1
    }
}

/**
 * Денежный журнал в памяти: баланс, статусы и настоящие подписи (подписывает [me]). Доставка и чеки — настоящий kit Handover,
 * поэтому тесты сценариев проверяют реальные переходы статусов, а не заглушки.
 */
class FakePaymentLedger(private val me: TestPlayer, balance: Long = 100) : PaymentLedger {
    private val balanceFlow = MutableStateFlow(balance)
    var balance: Long
        get() = balanceFlow.value
        set(value) { balanceFlow.value = value }

    /** Строки журнала для экранов — тест задаёт их сам. */
    val entries = MutableStateFlow<List<TransactionEntity>>(emptyList())
    val status = mutableMapOf<String, String>()
    val recipients = mutableMapOf<String, String>()
    val credited = mutableListOf<Mb10Qr.Transaction>()
    private val handover = Handover(MemoryJournal(status) { recipients[it] })

    override fun observeAll(): Flow<List<TransactionEntity>> = entries
    override fun observeBalance(): Flow<Long> = balanceFlow

    override fun signedTransaction(me: Identity, toPubKeyB64: String, amount: Long, memo: String, id: String): Mb10Qr.Transaction {
        val payload = com.megablok10.app.qr.Mb10QrCodec.transactionSignaturePayload(id, me.publicKeyB64, toPubKeyB64, amount, memo)
        return Mb10Qr.Transaction(id, me.publicKeyB64, toPubKeyB64, amount, memo, this.me.sign(payload))
    }

    override suspend fun recordOutgoingPending(tx: Mb10Qr.Transaction, toPubKeyB64: String): Boolean {
        if (tx.amount <= 0 || tx.amount > balance || tx.id in status) return false
        balance -= tx.amount
        status[tx.id] = TransactionStatus.PENDING
        recipients[tx.id] = toPubKeyB64
        return true
    }

    override suspend fun deliverOutgoing(id: String, willSend: Boolean, send: suspend () -> SendOutcome) = handover.deliver(id, willSend, send)

    override suspend fun cancelOutgoing(id: String): Boolean = status[id] == TransactionStatus.PENDING && status.remove(id) != null

    override suspend fun verifyAndConfirmReceipt(pendingTxId: String, receipt: Mb10Qr.Receipt) =
        handover.confirmByReceipt(pendingTxId, receipt.id, receipt.receiverPubKeyB64, receipt.signatureB64)

    override fun buildReceipt(me: Identity, transactionId: String) =
        Mb10Qr.Receipt(transactionId, me.publicKeyB64, this.me.sign(HandoverRules.receiptSignaturePayload(transactionId, me.publicKeyB64)))

    override suspend fun recordIncoming(myPublicKeyB64: String, tx: Mb10Qr.Transaction): Boolean {
        if (tx.toPubKeyB64 != myPublicKeyB64 || credited.any { it.id == tx.id }) return false
        credited += tx
        balance += tx.amount
        return true
    }
}

/** Журнал передач предметов в памяти (как [FakePaymentLedger]): коллекция — множество id предметов у игрока. */
class FakeItemLedger(private val me: TestPlayer, vararg owned: String) : ItemLedger {
    val owned = owned.toMutableSet()
    val status = mutableMapOf<String, String>()
    val recipients = mutableMapOf<String, String>()
    val accepted = mutableListOf<Mb10Qr.ItemTransfer>()
    private var next = 0
    private val handover = Handover(MemoryJournal(status) { recipients[it] })

    val entries = MutableStateFlow<List<ItemTransferEntity>>(emptyList())
    override fun observeAll(): Flow<List<ItemTransferEntity>> = entries

    override suspend fun sendShard(me: Identity, shardId: String, toPubKeyB64: String) = take(me, ItemKind.SHARD, shardId, toPubKeyB64)

    override suspend fun sendDaemon(me: Identity, daemon: Daemon, toPubKeyB64: String) = take(me, ItemKind.DAEMON, daemon.id, toPubKeyB64)

    private fun take(me: Identity, kind: ItemKind, itemId: String, to: String): Mb10Qr.ItemTransfer? {
        if (to == me.publicKeyB64 || !owned.remove(itemId)) return null
        val id = "item-${++next}"
        status[id] = TransactionStatus.PENDING
        recipients[id] = to
        return Mb10Qr.ItemTransfer(id, me.publicKeyB64, to, kind, itemId, this.me.sign("$id|$itemId"))
    }

    override suspend fun deliverOutgoing(id: String, willSend: Boolean, send: suspend () -> SendOutcome) = handover.deliver(id, willSend, send)

    override suspend fun cancelOutgoing(id: String): Boolean = status[id] == TransactionStatus.PENDING && status.remove(id) != null

    override suspend fun verifyAndConfirmReceipt(id: String, receipt: Mb10Qr.Receipt) =
        handover.confirmByReceipt(id, receipt.id, receipt.receiverPubKeyB64, receipt.signatureB64)

    override suspend fun acceptIncoming(myPubKeyB64: String, card: Mb10Qr.ItemTransfer): Boolean {
        if (card.toPubKeyB64 != myPubKeyB64 || accepted.any { it.id == card.id }) return false
        accepted += card
        owned += card.payload
        return true
    }

    override fun buildReceipt(me: Identity, id: String) =
        Mb10Qr.Receipt(id, me.publicKeyB64, this.me.sign(HandoverRules.receiptSignaturePayload(id, me.publicKeyB64)))
}

/** SharedPreferences в памяти — для IdentityStore/CollectorSettings в JVM-тестах (apply и commit пишут сразу). */
class MemoryPrefs : SharedPreferences {
    val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun getString(key: String, defValue: String?) = values[key] as String? ?: defValue
    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: MutableSet<String>?) = values[key] as MutableSet<String>? ?: defValues
    override fun getInt(key: String, defValue: Int) = values[key] as Int? ?: defValue
    override fun getLong(key: String, defValue: Long) = values[key] as Long? ?: defValue
    override fun getFloat(key: String, defValue: Float) = values[key] as Float? ?: defValue
    override fun getBoolean(key: String, defValue: Boolean) = values[key] as Boolean? ?: defValue
    override fun contains(key: String) = key in values
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removed = mutableSetOf<String>()
        private var clear = false
        override fun putString(key: String, value: String?) = apply { pending[key] = value }
        override fun putStringSet(key: String, values: MutableSet<String>?) = apply { pending[key] = values }
        override fun putInt(key: String, value: Int) = apply { pending[key] = value }
        override fun putLong(key: String, value: Long) = apply { pending[key] = value }
        override fun putFloat(key: String, value: Float) = apply { pending[key] = value }
        override fun putBoolean(key: String, value: Boolean) = apply { pending[key] = value }
        override fun remove(key: String) = apply { removed += key }
        override fun clear() = apply { clear = true }
        override fun commit(): Boolean {
            if (clear) values.clear()
            removed.forEach { values.remove(it) }
            pending.forEach { (k, v) -> if (v == null) values.remove(k) else values[k] = v }
            return true
        }
        override fun apply() { commit() }
    }
}

/** Таблица контактов в памяти (порядок — по позывному, как ORDER BY callsign). */
class FakeCharacterDao(vararg contacts: CharacterEntity) : CharacterDao {
    val rows = MutableStateFlow(contacts.sortedBy { it.callsign })
    override fun observeAll(): Flow<List<CharacterEntity>> = rows
    override suspend fun upsert(character: CharacterEntity) {
        rows.value = (rows.value.filter { it.publicKeyB64 != character.publicKeyB64 } + character).sortedBy { it.callsign }
    }
}

/** Уведомления игроку в памяти. */
class RecordingNotices : PlayerNotices {
    val shown = mutableListOf<String>()
    override fun show(text: String) { shown += text }
}

/** Коллекция шардов в памяти — как [FakePaymentLedger], минимальный порт для CyberdeckViewModel/ScanObject. */
class FakeShardCollection(vararg initial: Mb10Qr.Shard) : ShardCollection {
    val items = MutableStateFlow(initial.toList())
    val decryptedIds = mutableListOf<String>()
    override fun observeAll(): Flow<List<Mb10Qr.Shard>> = items

    override suspend fun add(shard: Mb10Qr.Shard, reason: String, sourceRef: String?, creditMoney: Boolean, decrypted: Boolean) {
        items.value = items.value + shard.copy(decrypted = decrypted)
    }

    override suspend fun markDecrypted(id: String) {
        decryptedIds += id
        items.value = items.value.map { if (it.id == id) it.copy(decrypted = true) else it }
    }
}

/** Коллекция демонов в памяти. [seedCalls] считает вызовы ensureSeeded — идемпотентность (не пересеивает непустую коллекцию) проверяет тест. */
class FakeDaemonCollection(vararg initial: Daemon) : DaemonCollection {
    val items = MutableStateFlow(initial.toList())
    var seedCalls = 0
    override fun observeAll(): Flow<List<Daemon>> = items
    override suspend fun ensureSeeded() {
        seedCalls++
        if (items.value.isEmpty()) items.value = listOf(Daemon("seed", "Datamine V1", listOf("1C", "55")))
    }
}

/**
 * Инбокс чата в памяти: лента у каждой фракции — свой Flow (как настоящий ChatStore.observeFaction фильтрует по фракции в
 * запросе) — тест может проверить, что смена фракции персонажа переподписывает ленту, а не просто ждёт новых элементов в общей.
 */
class FakeChatInbox : ChatInbox {
    private val factionFeeds = mutableMapOf<String, MutableStateFlow<List<ChatMessageEntity>>>()
    val recentThreads = MutableStateFlow<List<ChatMessageEntity>>(emptyList())
    val sentFaction = mutableListOf<String>()

    fun factionFeed(faction: String): MutableStateFlow<List<ChatMessageEntity>> = factionFeeds.getOrPut(faction) { MutableStateFlow(emptyList()) }

    override fun observeFaction(faction: String): Flow<List<ChatMessageEntity>> = factionFeed(faction)
    override fun observeRecentDirectThreads(myPubKey: String): Flow<List<ChatMessageEntity>> = recentThreads
    override suspend fun sendFaction(identity: Identity, body: String) { sentFaction += body }
}

/** Звонки в памяти — состояние и журнал задаёт тест, действия только записываются (как настоящий CallManager делает WebRTC). */
class FakeCallControls(initial: CallUiState = CallUiState()) : CallControls {
    override val state = MutableStateFlow(initial)
    val log = MutableStateFlow<List<CallLogEntity>>(emptyList())
    val started = mutableListOf<OnlinePlayer>()
    var accepted = 0
    var ended = 0
    override fun observeLog(): Flow<List<CallLogEntity>> = log
    override fun startOutgoingCall(identity: Identity, peer: OnlinePlayer) { started += peer }
    override fun accept(identity: Identity) { accepted++ }
    override fun endCall(identity: Identity) { ended++ }
}

/** Справочник пиров без сети: видно никого (или [online]), отправка — [outcome] на любой адрес. */
fun testPeerDirectory(vararg online: OnlinePlayer, outcome: SendOutcome = SendOutcome.NOT_REACHED) =
    PeerDirectory(
        { online.map { PeerInfo(it.pubKeyB64, it.callsign, it.faction, "10.0.0.1", 40_000) } },
        MutableStateFlow(online.toList()),
    ) { _, _, _ -> outcome }
