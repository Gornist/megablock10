package com.megablok10.app.data

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.items.ItemPayload
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.RoomTest
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Изменение игровых данных и запись о нём для мастера — один коммит, номера записей не повторяются после перезапуска.
 * На настоящей Room: сбой посреди операции (подпись записи бросает — как смерть процесса до коммита) откатывает всё целиком.
 */
@RunWith(RobolectricTestRunner::class)
class ChangeRecordTransactionsTest : RoomTest() {
    private val bob = TestPlayer("Bob")
    private val shard = Mb10Qr.Shard("shard-1", decryptAction = false, tier = 1, valueHint = "", title = "Чертёж", meta = "", body = "текст")

    @Test fun seqSurvivesRestartAndIsNeverReused() = runBlocking {
        wallet.creditShardMoney("s1", 10, "Шард")
        wallet.creditShardMoney("s2", 20, "Шард")
        // Сервер подтвердил — очередь пуста; прежний счётчик в настройках при этом отставал бы (apply() не успел на диск).
        db.pendingChangeRecordDao().deleteByIds(records().map { it.id })
        restart()
        wallet.creditShardMoney("s3", 30, "Шард")
        assertEquals(listOf(3L), records().map { it.seq })
    }

    @Test fun seqContinuesFromThePreviousCounterAndTheQueue() = runBlocking {
        // До версии базы 15 счётчик жил в SharedPreferences: нумерация продолжается с него...
        prefs.edit().putLong("next_change_seq", 41).commit()
        wallet.creditShardMoney("s1", 10, "Шард")
        assertEquals(42L, records().single().seq)
    }

    @Test fun seqStartsAboveTheQueueIfThePreviousCounterLagged() = runBlocking {
        // ...или с очереди, если настройки отстали от неё (запись сохранилась, а apply() счётчика — нет).
        prefs.edit().putLong("next_change_seq", 41).commit()
        db.pendingChangeRecordDao().insert(PendingChangeRecordEntity("old", me.publicKeyB64, 45, 1, "balance", "0", "1", "SHARD_SCAN", null, me.publicKeyB64, "sig"))
        wallet.creditShardMoney("s1", 10, "Шард")
        assertEquals(listOf(45L, 46L), records().map { it.seq })
    }

    @Test fun moneyAndItsRecordCommitTogether() = runBlocking {
        failOnSign = 1
        assertTrue(runCatching { wallet.creditShardMoney("s1", 50, "Шард") }.isFailure)
        assertEquals("деньги без записи для мастера не остаются", 0L, balance())
        assertTrue(records().isEmpty())

        wallet.creditShardMoney("s1", 50, "Шард")
        assertEquals(50L, balance())
        assertEquals("номер сорвавшейся записи откатился вместе с ней", listOf(1L), records().map { it.seq })
    }

    @Test fun shardMoneyAndBothRecordsCommitTogether() = runBlocking {
        // Шард несёт деньги: шард, зачисление и две записи (баланс, шард) — один коммит. Сбой на последней записи откатывает всё.
        val rich = shard.copy(moneyAmount = 70)
        wallet.creditShardMoney("warmup", 1, "Шард")   // первая подпись проходит, сбой — на записи шарда
        assertTrue(runCatching { failAfterFirstSign { shards.add(rich) } }.isFailure)
        assertNull(shards.get(rich.id))
        assertEquals(1L, balance())
        assertEquals(1, records().size)

        shards.add(rich)
        assertNotNull(shards.get(rich.id))
        assertEquals(71L, balance())
        assertEquals(listOf("balance", "balance", "shards.add"), records().map { it.field })
    }

    @Test fun concurrentBalanceChangesFormAnUnbrokenChain() = runBlocking {
        wallet.setStartingBalance("prov-1", 100)
        (1..30).map { n -> async(Dispatchers.Default) { wallet.creditContainerEddies("attempt-$n", n.toLong(), "Контейнер") } }.awaitAll()

        val chain = records().filter { it.field == ChangeField.BALANCE }
        assertEquals(31, chain.size)
        chain.zipWithNext().forEach { (a, b) -> assertEquals("«было» записи ${b.seq} — это «стало» записи ${a.seq}", a.newValue, b.oldValue) }
        assertEquals((100 + (1..30).sum()).toString(), chain.last().newValue)
        assertEquals(100L + (1..30).sum(), balance())
    }

    @Test fun acceptedItemAndItsRecordCommitTogether() = runBlocking {
        val card = shardCardFromBob()
        failOnSign = 1
        assertTrue(runCatching { items.acceptIncoming(me.publicKeyB64, card) }.isFailure)
        assertNull("отметка «принято» не осталась без предмета", db.itemTransferDao().get(card.id))
        assertNull(shards.get(shard.id))

        restart()
        assertTrue("повторное «Принять» после сбоя выдаёт предмет", items.acceptIncoming(me.publicKeyB64, card))
        assertNotNull(shards.get(shard.id))
        assertFalse("и только один раз", items.acceptIncoming(me.publicKeyB64, card))
    }

    @Test fun cancelledTransferAndReturnedItemCommitTogether() = runBlocking {
        shards.add(shard)
        val sent = items.sendShard(me, shard.id, bob.key)!!
        assertNull(shards.get(shard.id))

        failOnSign = 1
        assertTrue(runCatching { items.cancelOutgoing(sent.id) }.isFailure)
        assertNotNull("передача не отменилась без возврата предмета", db.itemTransferDao().get(sent.id))
        assertNull(shards.get(shard.id))

        assertTrue(items.cancelOutgoing(sent.id))
        assertNotNull(shards.get(shard.id))
    }

    private fun shardCardFromBob(): Mb10Qr.ItemTransfer {
        val payload = ItemPayload.encodeShard(shard)
        val sig = bob.sign(Mb10QrCodec.itemTransferSignaturePayload("item-1", bob.key, me.publicKeyB64, ItemKind.SHARD, payload))
        return Mb10Qr.ItemTransfer("item-1", bob.key, me.publicKeyB64, ItemKind.SHARD, payload, sig)
    }

    /** Сбой на второй подписи внутри [block] (первая запись проходит, вторая — нет). */
    private suspend fun <R> failAfterFirstSign(block: suspend () -> R): R {
        failOnSign = 2
        return try { block() } finally { failOnSign = 0 }
    }
}
