package com.megablok10.app.collector

import com.megablok10.app.data.ACCEPTED_RETENTION_MS
import com.megablok10.app.testing.RoomTest
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Журнал подтверждённых записей на настоящей Room: принятые сервером уходят из очереди, но хранятся; если сервер восстановили
 * из резервной копии и он знает меньше, записи сверх его последнего seq возвращаются в очередь и уходят снова.
 */
@RunWith(RobolectricTestRunner::class)
class AcceptedJournalTest : RoomTest() {
    private val queue get() = RoomChangeQueue(db.pendingChangeRecordDao(), db.sequenceDao(), identity::legacyChangeSeq, db.acceptedChangeRecordDao(), transactor, now = { clock })

    @Test fun acceptedRecordsAreKeptAndComeBackWhenTheServerLostThem() = runBlocking {
        (1..3).forEach { wallet.creditShardMoney("s$it", 10, "Шард") }
        val ids = records().map { it.id }
        queue.markAccepted(ids)
        assertTrue("принятые ушли из очереди", records().isEmpty())

        assertEquals("сервер знает всё — возвращать нечего", 0, queue.requeueAcceptedAbove(me.publicKeyB64, 3))
        assertEquals(2, queue.requeueAcceptedAbove(me.publicKeyB64, 1))
        assertEquals("вернулись те же записи, что сервер потерял", listOf(2L, 3L), records().map { it.seq })
        assertEquals(ids.drop(1), records().map { it.id })
        assertEquals("чужой ключ — не наше", 0, queue.requeueAcceptedAbove("кто-то другой", 0))
    }

    @Test fun journalKeepsRecordsForTheRetentionPeriodOnly() = runBlocking {
        wallet.creditShardMoney("old", 10, "Шард")
        queue.markAccepted(records().map { it.id })
        clock += ACCEPTED_RETENTION_MS + 1
        wallet.creditShardMoney("new", 10, "Шард")
        queue.markAccepted(records().map { it.id })   // заодно чистит журнал от просроченного

        assertEquals("старше срока хранения — не возвращается", 1, queue.requeueAcceptedAbove(me.publicKeyB64, 0))
        assertEquals(listOf(2L), records().map { it.seq })
    }
}
