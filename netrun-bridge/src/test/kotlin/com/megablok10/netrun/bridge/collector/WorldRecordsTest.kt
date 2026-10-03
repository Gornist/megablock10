package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.signaturePayload
import com.megablok10.kit.time.Clock
import com.megablok10.kit.time.ManualClock
import com.megablok10.netrun.bridge.Auditor
import com.megablok10.netrun.bridge.CommitHook
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.Move
import com.megablok10.netrun.bridge.MoveTo
import com.megablok10.netrun.bridge.StockItem
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueFixture
import com.megablok10.netrun.bridge.phone.WorldJournal
import com.megablok10.netrun.bridge.phone.WorldKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Записи мира (C2, раздел 2) выводятся из документов Моста: настоящие операции `ValueOps` на настоящей базе, затем очередь
 * [WorldRecordQueue]. Операции с ценностями о записях не знают — проверяем и то, что они появились, и то, что их нет там, где C2 их не просит.
 */
class WorldRecordsTest {
    @get:Rule val tmp = TemporaryFolder()

    private class Rig(val f: ValueFixture, val key: WorldKey = WorldKey.generate(), clock: Clock = ManualClock(T0_MS)) {
        val sync = WorldSync(f.store, key, null, CoroutineScope(Dispatchers.Unconfined), clock = clock)
        fun records(): List<ChangeRecord> = runBlocking { sync.queue.nextBatch(1000) }
        fun reasons(): List<String> = records().map { it.reason }
        fun of(reason: String): List<ChangeRecord> = records().filter { it.reason == reason }
    }

    private fun rig(path: String = ":memory:") = Rig(ValueFixture(path))

    private fun value(r: ChangeRecord): JsonObject = Json.parseToJsonElement(r.newValue!!) as JsonObject

    private fun Rig.submit(rid: String = "enter:e1"): String {
        val r = f.ops.submitDeck(f.test, rid, f.keyA, "Призрак", "t03", listOf("it_dA1", "it_dA2"), "it_dA1")
        assertTrue(r.body.toString(), r.ok)
        return f.sessionOf(r)
    }

    private fun Rig.enterActive(): String = submit().also { f.activate(it) }

    private fun Rig.finish(sid: String, outcome: String, disconnect: Boolean, vararg moves: Move) =
        f.ops.finishRun(f.world, "finish:$sid", sid, outcome, "node_07", disconnect, moves.toList()).also { assertTrue(it.body.toString(), it.ok) }

    // ---------- вход ----------

    @Test fun enterWritesOneSignedNetEnter() {
        val rig = rig()
        val sid = rig.submit()
        val r = rig.records().single()
        assertEquals("w:net.run:${rig.f.store.epoch}:${rig.f.store.seq}:$sid", r.id) // номер транзакции входа — последней в базе
        assertEquals("net.run", r.field)
        assertEquals("NET_ENTER", r.reason)
        assertEquals(sid, r.sourceRef)
        assertEquals(rig.key.publicB64, r.subjectKeyB64)
        assertEquals(rig.key.publicB64, r.actor)
        assertNull(r.oldValue)
        assertEquals(SEQ0 + 1, r.seq)
        assertTrue(Ecdsa.verify(rig.key.publicB64, r.signaturePayload(), r.signature))
        val v = value(r)
        assertEquals(sid, VJ.str(v, "session"))
        assertEquals(rig.f.keyA, VJ.str(v, "runner"))
        assertEquals("Призрак", VJ.str(v, "callsign"))
        assertEquals("t03", VJ.str(v, "terminal"))
        assertEquals("node_07", VJ.str(v, "node"))
        assertEquals(2L, VJ.lng(v, "deck"))
        assertTrue(VJ.bool(v, "protected"))
        assertEquals(rig.f.store.get("session", sid)!!.updated, r.happenedAt)
    }

    @Test fun confirmByTriggerAndPlainWritesAddNothing() {
        val rig = rig()
        val sid = rig.submit()
        rig.f.activate(sid)
        rig.f.store.put("node", "node_09", 0, rig.f.obj("tier" to "STANDARD", "eddies" to 5L))
        assertEquals(listOf("NET_ENTER"), rig.reasons())
    }

    @Test fun refusedEntryWritesNothing() {
        val rig = rig()
        // терминала нет: отказ, предметы возвращаются в outbox, записей мира нет
        val r = rig.f.ops.submitDeck(rig.f.test, "enter:bad", rig.f.keyA, "Призрак", "t99", listOf("it_dA1", "it_dA2"), "it_dA1")
        assertTrue(!r.ok)
        assertEquals(emptyList<ChangeRecord>(), rig.records())
    }

    // ---------- выход ----------

    @Test fun cleanFinishWritesTakeAndExit() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.f.ops.takeFromNode(rig.f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1")
        rig.f.ops.takeFromNode(rig.f.world, "take:$sid:eddies", sid, "node_07", null, 50)
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE))
        // эдди и переходы deck → outbox записей предмета не дают; взятие шарда из узла — даёт
        assertEquals(listOf("NET_ENTER", "NET_ITEM_OWNER", "NET_EXIT"), rig.reasons())
        assertEquals(listOf(SEQ0 + 1, SEQ0 + 2, SEQ0 + 3), rig.records().map { it.seq })
        val exit = rig.of("NET_EXIT").single()
        assertEquals("w:net.run:${rig.f.store.epoch}:${rig.f.store.seq}:$sid", exit.id) // выход — последняя транзакция
        val v = value(exit)
        assertEquals("clean", VJ.str(v, "outcome"))
        assertEquals(3L, VJ.lng(v, "returned"))
        assertEquals(0L, VJ.lng(v, "burned"))
        assertEquals(0L, VJ.lng(v, "left_in_node"))
        assertEquals(50L, VJ.lng(v, "eddies_paid"))
        assertEquals(0L, VJ.lng(v, "lockdown_until"))
        assertEquals(0L, VJ.lng(v, "duration_s")) // часы стенда идут по миллисекунде: забег короче секунды
        val take = value(rig.of("NET_ITEM_OWNER").single())
        assertEquals("node:node_07", VJ.str(take, "from"))
        assertEquals("deck:$sid", VJ.str(take, "to"))
        assertEquals("take_from_node", VJ.str(take, "op"))
        assertEquals("take:$sid:it_sh1", VJ.str(take, "rid"))
        assertEquals("SHARD", VJ.str(take, "kind"))
        assertEquals(rig.f.keyA, VJ.str(take, "runner"))
    }

    @Test fun emergencyCountsBurnedAndLeftInNode() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.f.ops.takeFromNode(rig.f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1")
        rig.finish(sid, "emergency", false, Move("it_dA2", MoveTo.BURNED), Move("it_sh1", MoveTo.NODE))
        val v = value(rig.of("NET_EXIT").single())
        assertEquals("emergency", VJ.str(v, "outcome"))
        assertEquals(1L, VJ.lng(v, "returned"))
        assertEquals(1L, VJ.lng(v, "burned"))
        assertEquals(1L, VJ.lng(v, "left_in_node"))
        val items = rig.of("NET_ITEM_OWNER").map { value(it) }.associateBy { VJ.str(it, "item") }
        val burned = items.getValue("it_dA2")
        assertEquals("deck:$sid", VJ.str(burned, "from"))
        assertEquals("burned:$sid", VJ.str(burned, "to"))
        assertEquals("run.finish", VJ.str(burned, "op"))
        assertEquals("finish:$sid", VJ.str(burned, "rid"))
        assertEquals(sid, VJ.str(burned, "session"))
        assertEquals("node:node_07", VJ.str(items.getValue("it_sh1"), "to"))
    }

    @Test fun durationIsExactlyFromTheTriggerWhenConfirmed() {
        val rig = rig()
        val sid = rig.submit()
        rig.f.advance(30_000) // игрок ещё не нажал курок
        val s = rig.f.store.get("session", sid)!!
        rig.f.store.put("session", sid, s.ver, VJ.with(s.data, "state" to VJ.p("active"), "confirmed_at" to VJ.p(rig.f.clock())))
        rig.f.advance(95_000)
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE))
        assertEquals(95L, VJ.lng(value(rig.of("NET_EXIT").single()), "duration_s")) // от курка, не от создания (125)
    }

    @Test fun durationIsExactlyFromCreationWhenThereWasNoTrigger() {
        val rig = rig()
        val sid = rig.enterActive() // confirmed_at = 0: курка в документе нет
        rig.f.advance(125_000)
        rig.finish(sid, "emergency", false, Move("it_dA2", MoveTo.BURNED))
        assertEquals(125L, VJ.lng(value(rig.of("NET_EXIT").single()), "duration_s"))
    }

    @Test fun flatlineDurationIsExactToo() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.f.advance(41_000)
        rig.finish(sid, "black_ice", false, Move("it_dA2", MoveTo.NODE))
        assertEquals(41L, VJ.lng(value(rig.of("NET_FLATLINE").single()), "duration_s"))
    }

    @Test fun softIceReportsLockdownDeadline() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.finish(sid, "soft_ice", false, Move("it_dA2", MoveTo.PHONE))
        val v = value(rig.of("NET_EXIT").single())
        assertEquals("soft_ice", VJ.str(v, "outcome"))
        val until = VJ.lng(rig.f.store.get("node", "node_07")!!.data, "lockdown_until")
        assertTrue(until > 0)
        assertEquals(until, VJ.lng(v, "lockdown_until"))
    }

    @Test fun abortedEntryWritesExit() {
        val rig = rig()
        val sid = rig.submit()
        assertTrue(rig.f.ops.abortSession(rig.f.test, sid, "терминал не подтвердил").ok)
        assertEquals(listOf("NET_ENTER", "NET_EXIT"), rig.reasons())
        val v = value(rig.of("NET_EXIT").single())
        assertEquals("aborted", VJ.str(v, "outcome"))
        assertEquals(2L, VJ.lng(v, "returned"))
    }

    // ---------- флэтлайн ----------

    @Test fun blackIceWritesFlatlineInsteadOfExitAndNoSecondAlert() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.f.ops.takeFromNode(rig.f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1")
        rig.finish(sid, "black_ice", false, Move("it_dA2", MoveTo.NODE), Move("it_sh1", MoveTo.NODE))
        assertEquals(emptyList<ChangeRecord>(), rig.of("NET_EXIT"))
        assertEquals(emptyList<ChangeRecord>(), rig.of("NET_ALERT")) // тревога флэтлайна — это NET_FLATLINE
        val flat = rig.of("NET_FLATLINE").single()
        assertEquals("net.run", flat.field)
        assertEquals(sid, flat.sourceRef)
        val v = value(flat)
        assertEquals("black_ice", VJ.str(v, "outcome"))
        assertEquals(2L, VJ.lng(v, "left_in_node"))
        assertEquals("флэтлайн", VJ.str(v, "cause"))
        assertTrue(!VJ.bool(v, "disconnect"))
        assertEquals(rig.f.store.list("alert").single().id, VJ.str(v, "alert"))
        assertEquals(rig.f.keyA, VJ.str(v, "runner"))
        // оба предмета легли в узел: по записи на каждый (плюс взятие шарда до этого)
        assertEquals(3, rig.of("NET_ITEM_OWNER").size)
    }

    @Test fun disconnectBeforeFlatlineIsMarked() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.finish(sid, "black_ice", true, Move("it_dA2", MoveTo.NODE))
        val v = value(rig.of("NET_FLATLINE").single())
        assertTrue(VJ.bool(v, "disconnect"))
        assertEquals("обрыв до флэтлайна", VJ.str(v, "cause"))
    }

    // ---------- предметы ----------

    @Test fun leaveInNodeWritesItemOwner() {
        val rig = rig()
        val sid = rig.enterActive()
        assertTrue(rig.f.ops.leaveInNode(rig.f.world, "leave:$sid:it_dA2", sid, "node_07", "it_dA2").ok)
        val v = value(rig.of("NET_ITEM_OWNER").single())
        assertEquals("it_dA2", VJ.str(v, "item"))
        assertEquals("deck:$sid", VJ.str(v, "from"))
        assertEquals("node:node_07", VJ.str(v, "to"))
        assertEquals("leave_in_node", VJ.str(v, "op"))
        assertEquals("leave:$sid:it_dA2", VJ.str(v, "rid"))
    }

    @Test fun receiptFromPhoneWritesItemLeftTheNet() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE))
        assertEquals(emptyList<ChangeRecord>(), rig.of("NET_ITEM_OWNER")) // deck → outbox внутри Сети не пишется
        val tid = VJ.str(rig.f.store.get("item", "it_dA2")!!.data, "out_transfer")!!
        assertEquals(1, runBlocking { WorldJournal(rig.f.store).confirm(tid) })
        val v = value(rig.of("NET_ITEM_OWNER").single())
        assertEquals("outbox:${rig.f.keyA}", VJ.str(v, "from"))
        assertEquals("phone:${rig.f.keyA}", VJ.str(v, "to"))
        assertEquals("issue_to_phone", VJ.str(v, "op"))
        assertEquals(tid, VJ.str(v, "rid"))
        assertEquals(rig.f.keyA, VJ.str(v, "runner"))
    }

    @Test fun masterStockAndUnstockAreNotRunEventsButBurnedIsRecorded() {
        val rig = rig()
        val stocked = rig.f.ops.stockNode(rig.f.master, "stock:1", "node_07", listOf(StockItem("SHARD", "payload-1")), 0)
        assertTrue(stocked.ok)
        assertEquals(emptyList<ChangeRecord>(), rig.records()) // создание предмета в узле — не смена владельца
        val id = VJ.list(stocked.body, "items").single()
        assertTrue(rig.f.ops.unstockNode(rig.f.master, "unstock:1", "node_07", listOf(id), 0).ok)
        val v = value(rig.of("NET_ITEM_OWNER").single())
        assertEquals("burned:master", VJ.str(v, "to"))
        assertEquals("master.unstock_node", VJ.str(v, "op"))
    }

    // ---------- тревоги ----------

    @Test fun auditorAlertWritesOneNetAlert() {
        val rig = rig()
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        Auditor(rig.f.store).run() // повторный проход тревогу не дублирует
        val r = rig.of("NET_ALERT").single()
        assertEquals("net.alert", r.field)
        val alert = rig.f.store.list("alert").single()
        assertEquals("w:net.alert:${rig.f.store.epoch}:${rig.f.store.seq}:${alert.id}", r.id)
        assertEquals(alert.id, r.sourceRef)
        val v = value(r)
        assertEquals(alert.id, VJ.str(v, "alert"))
        assertEquals("auditor_item_owner", VJ.str(v, "kind"))
        assertEquals(listOf("it_weird"), VJ.list(v, "items"))
        assertTrue(VJ.str(v, "msg")!!.contains("it_weird"))
    }

    @Test fun requestsToTheMasterAndToTheNetAreNotAuditorAlerts() {
        // «Ждём мастера» и «Запрос к Сети» (MasterOps.raiseAlert) — тоже документы alert, но это не тревога аудитора, а звонок панели
        // мастера: в записи мира (NET_ALERT, «внимание» мастера на коллекторе) они не попадают, документы остаются.
        val rig = rig()
        rig.f.store.put("alert", "al_2_master_request", 0, rig.f.obj("kind" to "master_request", "msg" to "Ждём мастера: флэтлайн"))
        rig.f.store.put("alert", "al_3_net_query", 0, rig.f.obj("kind" to "net_query", "msg" to "Запрос к Сети от KEY_A: помогите"))
        assertEquals(emptyList<ChangeRecord>(), rig.records())
        assertEquals(setOf("al_2_master_request", "al_3_net_query"), rig.f.store.list("alert").map { it.id }.toSet())
        // тревога аудитора рядом по-прежнему пишется
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        assertEquals(listOf("auditor_item_owner"), rig.of("NET_ALERT").map { VJ.str(value(it), "kind") })
    }

    @Test fun alertRaisedAgainAfterTheMasterRemovedItGetsANewRecordId() {
        // Обычный жизненный цикл: аудитор поднял тревогу, мастер её снял (удалил документ), расхождение живо — аудитор поднял снова
        // с тем же id документа и ver = 1. Это второе появление: нужна вторая запись и другой id, иначе коллектор отвергнет «id already used».
        val rig = rig()
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        val first = rig.f.store.list("alert").single()
        rig.f.store.delete("alert", first.id, first.ver)
        Auditor(rig.f.store).run()
        val second = rig.f.store.list("alert").single()
        assertEquals(first.id, second.id)
        assertEquals(1L, second.ver)
        val records = rig.of("NET_ALERT")
        assertEquals(2, records.size)
        assertEquals(2, records.map { it.id }.toSet().size)
        assertEquals(listOf(first.id, first.id), records.map { it.sourceRef })
        // повтор отправки той же записи id не меняет
        assertEquals(records.map { it.id }, rig.of("NET_ALERT").map { it.id })
    }

    @Test fun veryLongAlertMessageStillFitsTheCollectorLimit() {
        val rig = rig()
        rig.f.store.put("alert", "al_big", 0, rig.f.obj("kind" to "auditor_x", "msg" to "я".repeat(10_000)))
        val r = rig.of("NET_ALERT").single()
        assertTrue(r.newValue!!.length <= WorldRecords.MAX_VALUE_CHARS)
        assertEquals("auditor_x", VJ.str(value(r), "kind"))
    }

    // ---------- идемпотентность и атомарность ----------

    @Test fun replayedOperationAndFailedOperationAddNothing() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE))
        val before = rig.records().size
        val again = rig.f.ops.finishRun(rig.f.world, "finish:$sid", sid, "clean", "node_07", false, listOf(Move("it_dA2", MoveTo.PHONE)))
        assertTrue(again.replayed)
        val wrong = rig.f.ops.takeFromNode(rig.f.world, "take:wrong", sid, "node_07", "it_dB1")
        assertTrue(!wrong.ok)
        assertEquals(before, rig.records().size)
    }

    @Test fun failedCommitLeavesNeitherDocumentsNorRecordsNorSeq() {
        val rig = rig()
        val inner = rig.f.store.commitHook!!
        rig.f.store.commitHook = CommitHook { c, ch, prev ->
            inner.beforeCommit(c, ch, prev)
            error("сбой после записи в очередь")
        }
        val failed = runCatching { rig.submit("enter:boom") }
        assertTrue(failed.isFailure)
        assertEquals(emptyList<ChangeRecord>(), rig.records())
        assertEquals("inbox:${rig.f.keyA}", rig.f.owner("it_dA1")) // документы откатились вместе с очередью
        rig.f.store.commitHook = inner
        rig.submit("enter:ok")
        assertEquals(SEQ0 + 1, rig.records().single().seq) // откатился и счётчик: номер не потерян
    }

    @Test fun failedDeriveLogsAnErrorWithDocumentIdsAndDoesNotRollBackDocuments() {
        // Известное ограничение: записи мира — отчёт, а не ценность. Сбой разбора событий игру не останавливает (документы фиксируются),
        // но записи за эту транзакцию не появятся, поэтому он виден в журнале как ERROR с id документов, а не как предупреждение.
        val f = ValueFixture(":memory:")
        val log = RecordingLog()
        val recorder = WorldRecorder(WorldRecordQueue(f.store), WorldKey.generate(), f.store.epoch, log)
        f.store.commitHook = CommitHook { c, changes, _ -> recorder.beforeCommit(c, changes) { error("сбой чтения прежнего документа") } }
        val session = f.store.put("session", "s_broken", 0, f.obj("state" to "pending", "runner" to f.keyA, "node" to "node_07"))
        assertEquals(session, f.store.get("session", "s_broken")) // документ зафиксирован
        val line = log.all.single { it.contains("world.derive_failed") }
        assertTrue(line, line.startsWith("E/WorldRecords "))
        assertTrue(line, line.contains("session/s_broken"))
        assertTrue(line, line.contains("IllegalStateException"))
        assertEquals(emptyList<ChangeRecord>(), runBlocking { WorldRecordQueue(f.store).nextBatch(10) })
        // и следующая транзакция проходит как обычно
        f.store.put("alert", "al_next", 0, f.obj("kind" to "auditor_x", "msg" to "m"))
        assertTrue(f.store.get("alert", "al_next") != null)
    }

    @Test fun everyKindOfRecordIsSignedByTheWorldKey() {
        val rig = rig()
        val sid = rig.enterActive()
        rig.f.ops.takeFromNode(rig.f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1")
        rig.finish(sid, "black_ice", false, Move("it_dA2", MoveTo.NODE), Move("it_sh1", MoveTo.NODE))
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        val all = rig.records()
        assertEquals(setOf("NET_ENTER", "NET_ITEM_OWNER", "NET_FLATLINE", "NET_ALERT"), all.map { it.reason }.toSet())
        for (r in all) {
            assertTrue(r.id, Ecdsa.verify(rig.key.publicB64, r.signaturePayload(), r.signature))
            assertTrue(r.id, r.id.length <= 100)
            assertTrue(r.newValue!!.length <= WorldRecords.MAX_VALUE_CHARS)
        }
        assertEquals(all.map { it.seq }, (1..all.size).map { SEQ0 + it })
    }

    // ---------- эпоха базы: сброс базы Моста не возвращает старые id ----------

    /** Один и тот же ход событий на пустой базе под данным ключом мира: вход, взятие, выход, тревога аудитора. */
    private fun idsOfFreshBase(key: WorldKey): List<String> {
        val rig = Rig(ValueFixture(":memory:"), key)
        val sid = rig.enterActive()
        rig.f.ops.takeFromNode(rig.f.world, "take:$sid:it_sh1", sid, "node_07", "it_sh1")
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE), Move("it_sh1", MoveTo.PHONE))
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        return rig.records().map { it.id }.also { rig.f.store.close() }
    }

    /** Эпоха в id: `w:<field>:<эпоха>:<txSeq>:<sourceRef>`. */
    private fun epochOf(id: String): String = id.split(":")[2]

    @Test fun resetBaseWithSameKeyDoesNotReuseRecordIds() {
        // Сбросили базу Моста, ключ мира тот же, `ver` снова с 1: иначе коллектор отвергнет такие id («id already used»), kit удалит запись.
        val key = WorldKey.generate()
        val first = idsOfFreshBase(key)
        val second = idsOfFreshBase(key)
        assertTrue(first.size >= 4)
        assertEquals(first.size, second.size)
        assertEquals(emptySet<String>(), first.toSet() intersect second.toSet())
    }

    @Test fun restartKeepsTheEpochSoRecordIdsStayStable() {
        val path = tmp.root.resolve("epoch.db").path
        val key = WorldKey.generate()
        val first = Rig(ValueFixture(path), key)
        first.enterActive()
        val before = first.records().map { it.id }
        first.f.store.close()

        val store = DocStore.open(path)
        val second = WorldSync(store, key, null, CoroutineScope(Dispatchers.Unconfined))
        store.put("alert", "al_next", 0, VJ.obj("kind" to VJ.p("auditor_x"), "msg" to VJ.p("m")))
        val after = runBlocking { second.queue.nextBatch(10) }.map { it.id }
        store.close()
        assertEquals(2, after.size)
        assertEquals(before, after.take(1))
        assertEquals(epochOf(before.single()), epochOf(after.last()))
        assertEquals(store.epoch, epochOf(after.last()))
    }

    // ---------- seq: сброс только файла базы при прежнем ключе мира ----------

    private fun seqsOfFreshBase(key: WorldKey, nowMs: Long): List<Long> {
        val rig = Rig(ValueFixture(":memory:"), key, ManualClock(nowMs))
        val sid = rig.enterActive()
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE))
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        return rig.records().map { it.seq }.also { rig.f.store.close() }
    }

    @Test fun freshBaseUnderTheSameKeyStartsAboveEverySeqOfTheEarlierOne() {
        // Ключ мира лежит в отдельном файле и переживает удаление базы; коллектор не принимает seq, который у этого ключа уже занят.
        val key = WorldKey.generate()
        val first = seqsOfFreshBase(key, T0_MS)
        val second = seqsOfFreshBase(key, T0_MS + HOUR_MS)
        assertTrue(first.size >= 3)
        assertEquals(first.size, second.size)
        assertTrue("$first и $second", second.min() > first.max())
        assertEquals((second.first()..second.last()).toList(), second) // внутри базы по-прежнему подряд
    }

    @Test fun restartContinuesTheBaseSeqNotTheClock() {
        val path = tmp.root.resolve("seq.db").path
        val key = WorldKey.generate()
        val first = Rig(ValueFixture(path), key, ManualClock(T0_MS))
        first.enterActive()
        val last = first.records().last().seq
        first.f.store.close()

        val store = DocStore.open(path)
        val second = WorldSync(store, key, null, CoroutineScope(Dispatchers.Unconfined), clock = ManualClock(T0_MS + HOUR_MS))
        store.put("alert", "al_next", 0, VJ.obj("kind" to VJ.p("auditor_x"), "msg" to VJ.p("m")))
        assertEquals(last + 1, runBlocking { second.queue.nextBatch(10) }.last().seq)
        store.close()
    }

    @Test fun baseWithRecordsButWithoutTheCounterContinuesFromItsMaxSeq() {
        val path = tmp.root.resolve("nocounter.db").path
        val key = WorldKey.generate()
        val first = Rig(ValueFixture(path), key, ManualClock(T0_MS))
        first.enterActive()
        val last = first.records().last().seq
        first.f.store.close()
        java.sql.DriverManager.getConnection("jdbc:sqlite:$path").use { c -> c.createStatement().use { it.execute("DELETE FROM meta WHERE key='world_record_seq'") } }

        val store = DocStore.open(path)
        val second = WorldSync(store, key, null, CoroutineScope(Dispatchers.Unconfined), clock = ManualClock(T0_MS + HOUR_MS))
        store.put("alert", "al_next", 0, VJ.obj("kind" to VJ.p("auditor_x"), "msg" to VJ.p("m")))
        assertEquals(last + 1, runBlocking { second.queue.nextBatch(10) }.last().seq)
        store.close()
    }

    @Test fun queueAndSeqSurviveRestart() {
        val path = tmp.root.resolve("w.db").path
        val key = WorldKey.generate()
        val first = Rig(ValueFixture(path), key)
        first.enterActive()
        first.f.store.close()

        val store = DocStore.open(path)
        val second = WorldSync(store, key, null, CoroutineScope(Dispatchers.Unconfined))
        assertEquals(listOf("NET_ENTER"), runBlocking { second.queue.nextBatch(10) }.map { it.reason })
        // и новая запись продолжает нумерацию
        store.put("alert", "al_next", 0, VJ.obj("kind" to VJ.p("auditor_x"), "msg" to VJ.p("m")))
        assertEquals(listOf(SEQ0 + 1, SEQ0 + 2), runBlocking { second.queue.nextBatch(10) }.map { it.seq })
        store.close()
    }

    private companion object {
        const val T0_MS = 1_790_000_000_000L
        const val HOUR_MS = 3_600_000L

        /** Свежая база начинает счёт с времени в секундах: первая запись получает `SEQ0 + 1`. */
        const val SEQ0 = T0_MS / 1000
    }
}
