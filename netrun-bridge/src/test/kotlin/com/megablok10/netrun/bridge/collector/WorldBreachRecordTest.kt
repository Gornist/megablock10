package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.time.ManualClock
import com.megablok10.netrun.bridge.BreachFixture
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.phone.WorldKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Запись `NET_BREACH` (docs/netrun-world-records.md, 2.7): одна на каждый записанный итог `run.breach`, отказы и повторы её не дают. */
class WorldBreachRecordTest {
    private val f = BreachFixture()
    private val sync = WorldSync(f.store, WorldKey.generate(), null, CoroutineScope(Dispatchers.Unconfined), clock = ManualClock(1_790_000_000_000L))

    private fun breachRecords(): List<ChangeRecord> = runBlocking { sync.queue.nextBatch(1000) }.filter { it.reason == "NET_BREACH" }

    private fun value(r: ChangeRecord): JsonObject = Json.parseToJsonElement(r.newValue!!) as JsonObject

    @Test fun successWritesOneRecordWithOutcomeEffectsAndAlert() {
        val sid = f.enterA()
        val r = f.breach(sid, f.req(sid, selected = listOf("it_ex", "it_miner")))
        assertTrue(r.body.toString(), r.ok)
        val rec = breachRecords().single()
        assertEquals("net.breach", rec.field)
        assertEquals(sid, rec.sourceRef)
        val v = value(rec)
        assertEquals(sid, VJ.str(v, "session"))
        assertEquals(f.keyA, VJ.str(v, "runner"))
        assertEquals("node_07", VJ.str(v, "node"))
        assertEquals("HARD", VJ.str(v, "tier"))
        assertEquals(1L, VJ.lng(v, "n"))
        assertEquals("SUCCESS", VJ.str(v, "outcome"))
        assertEquals("EXTRACT_SHARD,MINER", VJ.str(v, "effects"))
        assertEquals(VJ.lng(r.body, "eddies"), VJ.lng(v, "eddies"))
        assertEquals(1L, VJ.lng(v, "opened"))
        assertEquals(false, VJ.bool(v, "exhausted"))
        val alert = f.secAlerts().single()
        assertEquals(alert.id, VJ.str(v, "alert"))
        assertEquals(VJ.lng(alert.data, "send_at"), VJ.lng(v, "alert_at"))
    }

    @Test fun failWithoutSignalHasNullAlert() {
        val sid = f.enterA()
        f.breach(sid, f.req(sid, tier = "BASE", selected = listOf("it_ex"), matched = emptyList()))
        val v = value(breachRecords().single())
        assertEquals("FAIL", VJ.str(v, "outcome"))
        assertEquals(JsonNull, v["alert"])
        assertEquals(JsonNull, v["alert_at"])
        assertEquals(0L, VJ.lng(v, "eddies"))
    }

    @Test fun replayAndRefusalWriteNothingNew() {
        val sid = f.enterA()
        val q = f.req(sid, selected = listOf("it_ex", "it_miner"))
        f.breach(sid, q)
        assertTrue(f.breach(sid, q).replayed) // тот же rid: ответ из сохранённого, документы не менялись
        val again = f.breach(sid, f.req(sid, n = 2, selected = listOf("it_ex")))
        assertEquals("cooldown", again.code) // остывание узла: отказ документов не меняет
        assertEquals(1, breachRecords().size)
    }

    @Test fun secondAttemptIsSeparateRecord() {
        val sid = f.enterA()
        f.breach(sid, f.req(sid, tier = "BASE", selected = listOf("it_ex"), matched = emptyList())) // FAIL: остывания нет
        f.breach(sid, f.req(sid, n = 2, tier = "BASE", selected = listOf("it_ex"), matched = emptyList()))
        val records = breachRecords()
        assertEquals(listOf(1L, 2L), records.map { VJ.lng(value(it), "n") })
        assertEquals(2, records.map { it.id }.toSet().size) // у каждой своя транзакция, свой id
    }
}
