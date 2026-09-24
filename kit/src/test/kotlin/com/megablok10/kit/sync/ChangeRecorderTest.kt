package com.megablok10.kit.sync

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.time.ManualClock
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChangeRecorderTest {
    private val keys = Ecdsa.generateKeyPair()
    private val myKey = Ecdsa.encodeKey(keys.public)
    private var seq = 0L
    private val signer = object : RecordSigner {
        override val publicKeyB64 = myKey
        override fun nextSeq() = ++seq
        override fun sign(data: ByteArray) = Ecdsa.sign(keys.private, data)
    }
    private val queue = object : ChangeQueue {
        val rows = mutableListOf<ChangeRecord>()
        override suspend fun insert(record: ChangeRecord) { rows += record }
        override suspend fun nextBatch(limit: Int) = rows.take(limit)
        override suspend fun deleteByIds(ids: List<String>) { rows.removeAll { it.id in ids } }
        override suspend fun count() = rows.size
        override suspend fun oldestHappenedAt() = rows.minOfOrNull { it.happenedAt }
    }
    private val log = RecordingLog()
    private var woken = 0
    private var ids = 0

    private fun recorder(withSigner: RecordSigner? = signer) = ChangeRecorder(
        queue, { withSigner }, ManualClock(1_700_000_000_000L), log, tag = "ChangeRecordStore",
        sensitiveFields = setOf("announcement"), newId = { "id-${++ids}" }, onRecorded = { woken++ },
    )

    @Test fun recordIsSignedQueuedAndWakesTheSync() = runTest {
        val r = recorder().record("balance", "5", "6", "TRANSFER_OUT", sourceRef = "tx-1")!!
        assertEquals(ChangeRecord("id-1", myKey, 1, 1_700_000_000_000L, "balance", "5", "6", "TRANSFER_OUT", "tx-1", myKey, r.signature), r)
        assertTrue(Ecdsa.verify(myKey, r.signaturePayload(), r.signature))
        assertEquals(listOf(r), queue.rows)
        assertEquals(1, woken)
        assertTrue(log.has("I/ChangeRecordStore record.enqueued field=balance reason=TRANSFER_OUT old=5 new=6 seq=1 ref=tx-1"))
    }

    @Test fun seqGrowsAndSubjectAndActorCanBeOverridden() = runTest {
        val rec = recorder()
        rec.record("counters.alert", null, "{}", "ALERT_SENT")
        val second = rec.record("balance", "0", "10", "TRANSFER_IN", subjectKeyB64 = "someone", actor = "sender")!!
        assertEquals(2, second.seq)
        assertEquals("someone", second.subjectKeyB64)
        assertEquals("sender", second.actor)
    }

    @Test fun sensitiveValuesStayOutOfTheLog() = runTest {
        recorder().record("announcement", null, "секретный текст", "MASTER_OVERRIDE")
        assertFalse(log.has("секретный текст"))
        assertTrue(log.has("record.enqueued field=announcement"))
    }

    @Test fun withoutIdentityNothingIsRecorded() = runTest {
        assertNull(recorder(withSigner = null).record("balance", null, "1", "X"))
        assertTrue(queue.rows.isEmpty())
        assertEquals(0, woken)
        assertTrue(log.has("нет личности устройства — запись balance/X потеряна"))
    }
}
