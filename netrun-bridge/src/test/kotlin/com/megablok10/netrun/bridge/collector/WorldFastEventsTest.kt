package com.megablok10.netrun.bridge.collector

import com.megablok10.netrun.bridge.Auditor
import com.megablok10.netrun.bridge.CommitHook
import com.megablok10.netrun.bridge.Move
import com.megablok10.netrun.bridge.MoveTo
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueFixture
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Быстрые события на точки (docs/netrun-world-records.md, разделы 3 и 4) выводятся из документов Моста: настоящие операции `ValueOps`
 * на настоящей базе, затем [WorldFastEvents.derive] в том же хуке коммита, что и записи мира. Здесь — что и когда рождается, без сети.
 */
class WorldFastEventsTest {
    /** Стенд с хуком, который собирает всё, что вывел бы Мост за каждую транзакцию. */
    private class Rig(val f: ValueFixture = ValueFixture(":memory:")) {
        private val seen = ArrayList<FastEvent>()

        init {
            f.store.commitHook = CommitHook { _, changes, previous -> seen += WorldFastEvents.derive(changes, previous, f.store.epoch) }
        }

        /** События, появившиеся с прошлого вызова. */
        fun events(): List<FastEvent> = seen.toList().also { seen.clear() }

        fun kinds(): List<String> = events().map { it.kind }

        fun submit(rid: String = "enter:e1"): String {
            val r = f.ops.submitDeck(f.test, rid, f.keyA, "Призрак", "t03", listOf("it_dA1", "it_dA2"), "it_dA1")
            assertTrue(r.body.toString(), r.ok)
            return f.sessionOf(r)
        }

        fun enterActive(): String = submit().also { f.activate(it) }

        fun finish(sid: String, outcome: String, disconnect: Boolean = false, vararg moves: Move) =
            f.ops.finishRun(f.world, "finish:$sid", sid, outcome, "node_07", disconnect, moves.toList().ifEmpty { listOf(Move("it_dA2", MoveTo.NODE)) })
                .also { assertTrue(it.body.toString(), it.ok) }

        /** Записать в `session.world` поля [fields] поверх прежних, как это делает сервер мира. */
        fun world(sid: String, vararg fields: Pair<String, Any>) {
            val s = f.store.get("session", sid)!!
            val old = (s.data["world"] as? JsonObject) ?: JsonObject(emptyMap())
            val next = JsonObject(old + fields.associate { (k, v) -> k to if (v is Boolean) JsonPrimitive(v) else if (v is Number) JsonPrimitive(v) else JsonPrimitive(v.toString()) })
            f.store.put("session", sid, s.ver, VJ.with(s.data, "world" to next))
        }
    }

    // ---------- вход ----------

    @Test fun triggerMakesRunEnterAndSubmitDeckMakesNothing() {
        val rig = Rig()
        val sid = rig.submit()
        assertEquals(emptyList<FastEvent>(), rig.events()) // сдача деки — запись NET_ENTER, а не быстрое событие
        rig.f.activate(sid)
        val e = rig.events().single()
        val s = rig.f.store.get("session", sid)!!
        assertEquals(FastKinds.RUN_ENTER, e.kind)
        assertEquals("e:${rig.f.store.epoch}:${rig.f.store.seq}:run.enter:$sid", e.id)
        assertEquals("node_07", e.node)
        assertEquals("t03", e.terminal)
        assertEquals(sid, e.session)
        assertNull(e.level)
        assertEquals(5_000L, e.ttlMs)
        assertEquals(s.updated, e.ts)
    }

    @Test fun plainWritesAndRepeatedStateMakeNoEvents() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.events()
        val s = rig.f.store.get("session", sid)!!
        rig.f.store.put("session", sid, s.ver, VJ.with(s.data, "loot_eddies" to VJ.p(5L))) // active → active
        rig.f.store.put("node", "node_09", 0, rig.f.obj("tier" to "STANDARD", "eddies" to 5L, "lockdown_until" to 0L))
        rig.f.store.put("terminal", "t09", 0, rig.f.obj("node" to "node_09"))
        assertEquals(emptyList<FastEvent>(), rig.events())
    }

    // ---------- выход ----------

    @Test fun everyOrdinaryOutcomeMakesOnlyRunExit() {
        for (outcome in listOf("clean", "emergency")) {
            val rig = Rig()
            val sid = rig.enterActive()
            rig.events()
            rig.finish(sid, outcome, false, Move("it_dA2", if (outcome == "clean") MoveTo.PHONE else MoveTo.BURNED))
            val e = rig.events().single()
            assertEquals(outcome, FastKinds.RUN_EXIT, e.kind)
            assertEquals(listOf("node_07", "t03", sid), listOf(e.node, e.terminal, e.session))
        }
    }

    @Test fun abortedEntryMakesRunExit() {
        val rig = Rig()
        val sid = rig.submit()
        rig.events()
        assertTrue(rig.f.ops.abortSession(rig.f.test, sid, "терминал не подтвердил").ok)
        assertEquals(listOf(FastKinds.RUN_EXIT), rig.kinds())
    }

    @Test fun softIceMakesRunExitAndLockdownOfTheNodeWithTheSession() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.events()
        rig.finish(sid, "soft_ice", false, Move("it_dA2", MoveTo.PHONE))
        val events = rig.events()
        assertEquals(setOf(FastKinds.RUN_EXIT, FastKinds.LOCKDOWN), events.map { it.kind }.toSet())
        assertEquals(2, events.size)
        val lockdown = events.single { it.kind == FastKinds.LOCKDOWN }
        assertEquals("node_07", lockdown.node)
        assertNull(lockdown.terminal) // точки узла, не терминал
        assertEquals(sid, lockdown.session)
        assertEquals("e:${rig.f.store.epoch}:${rig.f.store.seq}:lockdown:node_07", lockdown.id)
        assertEquals(rig.f.store.get("node", "node_07")!!.updated, lockdown.ts)
    }

    @Test fun blackIceMakesFlatlineThenRunExit() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.events()
        rig.finish(sid, "black_ice", false, Move("it_dA2", MoveTo.NODE))
        val events = rig.events()
        assertEquals(listOf(FastKinds.FLATLINE, FastKinds.RUN_EXIT), events.map { it.kind }) // сначала отдельный звук, затем фон
        for (e in events) assertEquals(listOf("node_07", "t03", sid), listOf(e.node, e.terminal, e.session))
        assertEquals(2, events.map { it.id }.toSet().size) // одна транзакция, два вида — два id
        assertTrue(events.none { it.kind == FastKinds.LOCKDOWN }) // флэтлайн узел не закрывает
    }

    // ---------- trace и охота ----------

    @Test fun traceLevelChangeMakesOneEventNamedByTheLevelAndRepeatsMakeNone() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.events()
        rig.world(sid, "trace_level" to 0, "trace" to 0)
        assertEquals(emptyList<FastEvent>(), rig.events()) // первая запись NORMAL — не смена
        val seen = ArrayList<String?>()
        for (level in listOf(1, 1, 2, 3, 2, 0)) {
            rig.world(sid, "trace_level" to level, "trace" to level * 30)
            seen += rig.events().map { it.level }.let { if (it.isEmpty()) null else it.single() }
        }
        assertEquals(listOf("SUSPICIOUS", null, "TRACE", "LOCKDOWN", "TRACE", "NORMAL"), seen)
        rig.world(sid, "trace_level" to 9)
        assertEquals(emptyList<FastEvent>(), rig.events()) // числа не из перечня сервера мира не придумываем
    }

    @Test fun traceEventUsesTheCurrentNodeFromWorld() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.events()
        rig.world(sid, "node" to "node_08", "trace_level" to 2)
        val e = rig.events().single()
        assertEquals(FastKinds.TRACE_LEVEL, e.kind)
        assertEquals("TRACE", e.level)
        assertEquals("node_08", e.node) // точки узла, где игрок сейчас, а не куда его приняли
        assertEquals("t03", e.terminal)
        assertEquals(sid, e.session)
        assertEquals("e:${rig.f.store.epoch}:${rig.f.store.seq}:trace.level:$sid", e.id)
    }

    @Test fun huntStartMakesOneIceHuntAndEndMakesNone() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.events()
        rig.world(sid, "hunt" to true)
        val e = rig.events().single()
        assertEquals(FastKinds.ICE_HUNT, e.kind)
        assertNull(e.level)
        assertEquals(listOf("node_07", sid), listOf(e.node, e.session))
        rig.world(sid, "hunt" to true, "trace" to 80)
        rig.world(sid, "hunt" to false)
        assertEquals(emptyList<FastEvent>(), rig.events())
        rig.world(sid, "hunt" to true) // новая охота — новое событие
        assertEquals(listOf(FastKinds.ICE_HUNT), rig.kinds())
    }

    @Test fun worldWritesOfClosedSessionMakeNoTraceEvents() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.finish(sid, "clean", false, Move("it_dA2", MoveTo.PHONE))
        rig.events()
        rig.world(sid, "trace_level" to 3, "hunt" to true)
        assertEquals(emptyList<FastEvent>(), rig.events())
    }

    // ---------- локдаун узла ----------

    @Test fun masterLockdownMakesEventOnlyWhenTheNodeWasOpen() {
        val rig = Rig()
        val node = { rig.f.store.get("node", "node_07")!! }
        val until = rig.f.nowMs + 600_000
        rig.f.store.put("node", "node_07", node().ver, VJ.with(node().data, "lockdown_until" to VJ.p(until)))
        val e = rig.events().single()
        assertEquals(FastKinds.LOCKDOWN, e.kind)
        assertEquals("node_07", e.node)
        assertNull(e.session)
        // продление идущего локдауна, снятие и «срок в прошлом» — не события
        rig.f.store.put("node", "node_07", node().ver, VJ.with(node().data, "lockdown_until" to VJ.p(until + 600_000)))
        rig.f.store.put("node", "node_07", node().ver, VJ.with(node().data, "lockdown_until" to VJ.p(0L)))
        rig.f.store.put("node", "node_07", node().ver, VJ.with(node().data, "lockdown_until" to VJ.p(5L)))
        assertEquals(emptyList<FastEvent>(), rig.events())
    }

    // ---------- тревога мастеру ----------

    @Test fun newAuditorAlertMakesAlertMasterAndOnlyOnCreation() {
        val rig = Rig()
        val data = rig.f.obj("kind" to "auditor_item_owner", "msg" to "it_02bb: владелец deck:s_9f2c", "items" to "x")
        val a = rig.f.store.put("alert", "al_a_3f9c1e07b2d4", 0, data)
        val e = rig.events().single()
        assertEquals(FastKinds.ALERT_MASTER, e.kind)
        assertEquals("e:${rig.f.store.epoch}:${rig.f.store.seq}:alert.master:al_a_3f9c1e07b2d4", e.id)
        assertEquals(listOf(null, null, null, null), listOf(e.node, e.terminal, e.session, e.level)) // на площадку не идёт, привязки нет
        assertEquals(a.updated, e.ts)
        rig.f.store.put("alert", a.id, a.ver, VJ.with(a.data, "msg" to VJ.p("другой текст"))) // правка тревоги — не новая тревога
        assertEquals(emptyList<FastEvent>(), rig.events())
        // снята мастером и поднята аудитором заново: второе появление, свой id
        rig.f.store.delete("alert", a.id, rig.f.store.get("alert", a.id)!!.ver)
        assertEquals(emptyList<FastEvent>(), rig.events())
        rig.f.store.put("alert", a.id, 0, data)
        val again = rig.events().single()
        assertEquals(FastKinds.ALERT_MASTER, again.kind)
        assertTrue(again.id != e.id)
    }

    @Test fun flatlineAlertAndMasterCallsAreNotAlertMaster() {
        val rig = Rig()
        for ((i, kind) in listOf("flatline", "master_request", "net_query").withIndex()) rig.f.store.put("alert", "al_$i", 0, rig.f.obj("kind" to kind, "msg" to "m"))
        assertEquals(emptyList<FastEvent>(), rig.events())
    }

    @Test fun auditorFindsRealViolationAndMakesAlertMaster() {
        val rig = Rig()
        rig.f.item("it_weird", "weird:1", "x")
        Auditor(rig.f.store).run()
        val events = rig.events()
        assertTrue(events.toString(), events.isNotEmpty() && events.all { it.kind == FastKinds.ALERT_MASTER })
    }

    // ---------- id ----------

    @Test fun idsDifferBetweenBaseLivesAndFitTheLimit() {
        // Сброс базы под тем же ключом: номера транзакций снова с начала, эпоха новая — id событий не повторяются.
        val first = Rig()
        first.enterActive()
        val a = first.events().single()
        val second = Rig()
        second.enterActive()
        val b = second.events().single()
        assertEquals(a.id.split(":")[2], b.id.split(":")[2]) // тот же номер транзакции...
        assertTrue("${a.id} / ${b.id}", a.id.split(":")[1] != b.id.split(":")[1]) // ...но эпоха другая
        assertTrue(a.id.contains(first.f.store.epoch) && b.id.contains(second.f.store.epoch))
        val long = Rig()
        val sid = "s_" + "x".repeat(62)
        long.f.store.put("session", sid, 0, long.f.obj("state" to "active", "terminal" to "t".repeat(64), "node" to "n".repeat(64), "runner" to long.f.keyA))
        val e = long.events().single()
        assertTrue(e.id, e.id.length <= 100)
        assertTrue((e.node ?: "").length <= 100 && (e.terminal ?: "").length <= 100)
    }

    @Test fun catalogOfKindsMatchesWhatDeriveCanEmit() {
        val rig = Rig()
        val sid = rig.enterActive()
        rig.world(sid, "trace_level" to 2)
        rig.world(sid, "hunt" to true)
        rig.finish(sid, "soft_ice", false, Move("it_dA2", MoveTo.PHONE))
        val node = rig.f.store.get("node", "node_07")!!
        rig.f.store.put("node", "node_07", node.ver, VJ.with(node.data, "lockdown_until" to VJ.p(0L))) // мастер открыл узел: иначе вход в него отказан
        val sid2 = rig.f.enterActive(rig.f.keyB, "t04", "it_dB1", "it_dB2")
        rig.finish(sid2, "black_ice", false, Move("it_dB2", MoveTo.NODE))
        rig.f.store.put("alert", "al_x", 0, rig.f.obj("kind" to "auditor_x", "msg" to "m"))
        assertEquals(FastKinds.ALL.toSet(), rig.events().map { it.kind }.toSet())
    }
}
