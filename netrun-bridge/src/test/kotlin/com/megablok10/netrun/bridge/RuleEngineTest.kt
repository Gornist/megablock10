package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RuleEngineTest {
    private var now = 1_000_000L
    private val logs = ArrayList<String>()

    private fun obj(vararg p: Pair<String, Any>) = JsonObject(
        p.associate { (k, v) -> k to (if (v is Boolean) JsonPrimitive(v) else if (v is Long) JsonPrimitive(v) else JsonPrimitive(v as String)) },
    )

    private fun <T> withEngine(block: (DocStore, RuleEngine) -> T): T =
        DocStore.open(":memory:") { now }.use { s -> RuleEngine(s, { now }, { logs.add(it) }).use { block(s, it) } }

    @Test fun changeRuleSeesOnlyItsType() = withEngine { s, e ->
        val seen = ArrayList<String>()
        e.onChange("r", "terminal") { _, c -> seen.add(c.doc.id) }
        s.put("terminal", "t1", 0, obj())
        s.put("node", "n1", 0, obj())
        e.tick()
        assertEquals(listOf("t1"), seen)
    }

    @Test fun timerUsesSettingsAndFakeClock() = withEngine { s, e ->
        var runs = 0
        e.every("t", "period_s", 10) { runs++ }
        e.tick(); assertEquals(1, runs)
        now += 9_000; e.tick(); assertEquals(1, runs)
        now += 1_000; e.tick(); assertEquals(2, runs)
        s.put("settings", "global", 0, obj("period_s" to 60L))
        now += 10_000; e.tick(); assertEquals(2, runs)
        now += 50_000; e.tick(); assertEquals(3, runs)
    }

    @Test fun ruleCannotWriteValues() = withEngine { s, e ->
        e.onChange("greedy", "node") { ctx, _ -> ctx.update("node", "n1") { JsonObject(it + ("eddies" to JsonPrimitive(999L))) } }
        e.every("item_maker", "x", 1) { it.create("item", "it1", obj()) }
        s.put("node", "n1", 0, obj("eddies" to 5L))
        e.tick()
        assertEquals(JsonPrimitive(5L), s.get("node", "n1")!!.data["eddies"])
        assertEquals(null, s.get("item", "it1"))
        assertEquals(1L, e.failuresOf("greedy"))
        assertEquals(1L, e.failuresOf("item_maker"))
    }

    @Test fun failureDoesNotStopOtherRulesAndIsLogged() = withEngine { s, e ->
        var ok = 0
        e.onChange("bad", "terminal") { _, _ -> error("бум") }
        e.onChange("good", "terminal") { _, _ -> ok++ }
        s.put("terminal", "t1", 0, obj())
        s.put("terminal", "t2", 0, obj())
        e.tick()
        assertEquals(2, ok)
        assertEquals(2L, e.failures)
        assertEquals(2, logs.size)
        assertTrue(logs[0].contains("rule=bad") && logs[0].contains("бум"))
        assertTrue(e.lastError!!.contains("rule=bad"))
    }

    @Test fun cascadeIsBounded() = withEngine { s, _ ->
        RuleEngine(s, { now }, { logs.add(it) }, cascadeLimit = 5).use { e ->
            e.onChange("loop", "node") { ctx, c -> ctx.update("node", c.doc.id) { JsonObject(it + ("n" to JsonPrimitive(c.doc.ver))) } }
            s.put("node", "n1", 0, obj())
            e.tick()
            assertEquals(1L, e.failuresOf("engine"))
        }
    }

    @Test fun silentTerminalFlagsAndRecovers() = withEngine { s, e ->
        TerminalSilentRule(e).register()
        s.put("settings", "global", 0, obj("terminal_silent_s" to 30L))
        s.put("terminal", "t03", 0, obj("label" to "стойка"))
        e.tick()
        assertEquals(null, s.get("terminal", "t03")!!.data["silent"])

        now += 31_000; e.tick()
        assertEquals(JsonPrimitive(true), s.get("terminal", "t03")!!.data["silent"])
        val flagged = s.get("terminal", "t03")!!.ver

        // Собственная запись правила не считается жизнью терминала, флаг держится.
        now += 5_000; e.tick(); e.tick()
        assertEquals(JsonPrimitive(true), s.get("terminal", "t03")!!.data["silent"])
        assertEquals(flagged, s.get("terminal", "t03")!!.ver)

        // Терминал подал признак жизни (правка документа) — флаг снят.
        val d = s.get("terminal", "t03")!!
        s.put("terminal", "t03", d.ver, JsonObject(d.data + ("seen" to JsonPrimitive(now))))
        e.tick()
        assertEquals(JsonPrimitive(false), s.get("terminal", "t03")!!.data["silent"])
        assertEquals(0L, e.failures)

        // И снова молчит — флаг ставится заново.
        now += 31_000; e.tick()
        assertEquals(JsonPrimitive(true), s.get("terminal", "t03")!!.data["silent"])
    }

    @Test fun silentThresholdFollowsSettings() = withEngine { s, e ->
        TerminalSilentRule(e).register()
        s.put("terminal", "t1", 0, obj())
        now += 40_000; e.tick() // порога нет в настройках: умолчание 30 с
        assertEquals(JsonPrimitive(true), s.get("terminal", "t1")!!.data["silent"])
        s.put("terminal", "t2", 0, obj())
        s.put("settings", "global", 0, obj("terminal_silent_s" to 100L))
        now += 40_000; e.tick()
        assertEquals(null, s.get("terminal", "t2")!!.data["silent"])
    }
}
