package com.megablok10.app.testing

import androidx.room.Room
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.collector.RoomChangeQueue
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.data.RoomTransactor
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.wallet.TransactionStore
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.ChangeRecorder
import com.megablok10.kit.sync.RecordSigner
import org.junit.After
import org.robolectric.RuntimeEnvironment

/**
 * Основа тестов на настоящей Room (в памяти, под Robolectric): транзакции, откаты и выдача seq — то, что фейками не проверить.
 * Хранилища собраны так же, как в di.AppGraph. «Перезапуск процесса» — [restart]: новые экземпляры поверх той же базы,
 * всё, что жило только в памяти, пропадает.
 */
abstract class RoomTest {
    protected val db: Mb10Database = Room.inMemoryDatabaseBuilder(RuntimeEnvironment.getApplication(), Mb10Database::class.java).build()
    protected val prefs = MemoryPrefs()
    protected val identity = IdentityStore(prefs).also { it.getOrCreate("Alice", "Малстром") }
    protected val me get() = identity.current!!

    /**
     * Сбой посреди операции — как если бы процесс умер до коммита: N-я по счёту подпись записи для мастера бросает, транзакция
     * откатывается. 1 — ближайшая подпись, 2 — вторая (первая запись операции проходит), 0 — сбоев нет.
     */
    protected var failOnSign = 0

    protected var transactor = RoomTransactor(db)
    protected var changes = newRecorder()
    protected var wallet = TransactionStore(db, identity, changes, transactor)
    protected var shards = ShardStore(db.shardDao(), wallet, changes, transactor)
    protected var daemons = DaemonStore(db.daemonDao(), changes, transactor)
    protected var items = ItemTransferStore(db, identity, shards, daemons, transactor)

    private fun newRecorder(): ChangeRecorder {
        val queue = RoomChangeQueue(db.pendingChangeRecordDao(), db.sequenceDao(), identity::legacyChangeSeq)
        val signer = {
            identity.recordSigner()?.let { real ->
                object : RecordSigner {
                    override val publicKeyB64 = real.publicKeyB64
                    override fun sign(data: ByteArray): String {
                        if (failOnSign > 0 && --failOnSign == 0) error("процесс умер посреди операции")
                        return real.sign(data)
                    }
                }
            }
        }
        return ChangeRecorder(queue, signer, transactor = transactor)
    }

    /** Новый процесс поверх той же базы и тех же настроек. */
    protected fun restart() {
        transactor = RoomTransactor(db)
        changes = newRecorder()
        wallet = TransactionStore(db, identity, changes, transactor)
        shards = ShardStore(db.shardDao(), wallet, changes, transactor)
        daemons = DaemonStore(db.daemonDao(), changes, transactor)
        items = ItemTransferStore(db, identity, shards, daemons, transactor)
    }

    /** Очередь записей для мастера по порядку seq. */
    protected suspend fun records(): List<ChangeRecord> = db.pendingChangeRecordDao().nextBatch(Int.MAX_VALUE).map {
        ChangeRecord(it.id, it.subjectKeyB64, it.seq, it.happenedAt, it.field, it.oldValue, it.newValue, it.reason, it.sourceRef, it.actor, it.signature)
    }

    protected suspend fun balance(): Long = db.transactionDao().currentBalance()

    @After fun closeDb() = db.close()
}
