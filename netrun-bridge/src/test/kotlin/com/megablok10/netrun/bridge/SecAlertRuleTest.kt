package com.megablok10.netrun.bridge

import com.megablok10.kit.net.SendOutcome
import com.megablok10.netrun.bridge.phone.PhoneSender
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SecAlertRuleTest {
    private var now = 1_000_000L

    private class Sent(val key: String, val line: String)

    private class FakeSender(val online: Set<String>) : PhoneSender {
        val sent = ArrayList<Sent>()
        override fun isOnline(pubKeyB64: String) = pubKeyB64 in online
        override fun send(pubKeyB64: String, line: String): SendOutcome {
            sent += Sent(pubKeyB64, line)
            return SendOutcome.DELIVERED
        }
    }

    private fun arr(vararg s: String) = JsonArray(s.map { JsonPrimitive(it) })

    /** Мир: узел [tier] фракции «СБ», активная сессия, получатели k1 (в сети) и k2 (нет). */
    private fun run(tier: String = "NIGHTMARE", effects: List<String> = emptyList(), block: (DocStore, RuleEngine, FakeSender) -> Unit) {
        DocStore.open(":memory:") { now }.use { s ->
            RuleEngine(s, { now }, { }).use { e ->
                val sender = FakeSender(setOf("k1"))
                SecAlertRule(e, s, sender, { now }, { }).register()
                s.put("node", "n7", 0, VJ.obj("title" to VJ.p("Склад"), "tier" to VJ.p(tier), "owner_faction" to VJ.p("СБ")))
                s.put("settings", "sec", 0, VJ.obj("factions" to JsonObject(mapOf("СБ" to arr("k1", "k2")))))
                s.put("runner", "r1", 0, VJ.obj("faction" to VJ.p("Корпа")))
                s.put(
                    "session", "s1", 0,
                    VJ.obj(
                        "state" to VJ.p("active"), "terminal" to VJ.p("t03"), "node" to VJ.p("n7"), "runner" to VJ.p("r1"),
                        "callsign" to VJ.p("Призрак"), "world" to VJ.obj("trace_level" to VJ.p(0L), "effects" to arr(*effects.toTypedArray())),
                    ),
                )
                e.tick()
                block(s, e, sender)
            }
        }
    }

    private fun setLevel(s: DocStore, level: Long) {
        val d = s.get("session", "s1")!!
        val w = d.data["world"] as JsonObject
        s.put("session", "s1", d.ver, JsonObject(d.data + ("world" to JsonObject(w + ("trace_level" to JsonPrimitive(level))))))
    }

    @Test fun belowTraceNoSignal() = run { s, e, snd ->
        setLevel(s, 1); e.tick()
        assertTrue(snd.sent.isEmpty())
    }

    @Test fun traceSendsOnceWithExactFormat() = run { s, e, snd ->
        setLevel(s, 2); e.tick()
        assertEquals(listOf("k1"), snd.sent.map { it.key })
        assertEquals(
            "MB10CHAT:v1:FACTION:SEC-SYSTEM:U0VDLy9NQjEw:0KHQkQ==::1000000:" +
                "TUIxMDpTRUNBTEVSVDp2MTpuNzowS0hRdXRDNzBMRFF0Q0RDdHlEUmd0QzEwWURRdk5DNDBMM1FzTkM3SUhRd013PT06MzowSi9SZ05DNDBMZlJnTkN3MExvPToxMDAwMDAw",
            snd.sent[0].line,
        )
        // тот же уровень ещё раз, прочие тики — второго сигнала нет
        val d = s.get("session", "s1")!!
        s.put("session", "s1", d.ver, d.data)
        e.tick(); now += 5_000; e.tick()
        assertEquals(1, snd.sent.size)
        // новый уровень — новый сигнал
        setLevel(s, 3); e.tick()
        assertEquals(2, snd.sent.size)
    }

    @Test fun hardTierDelaysByDecideAndRevealsCallsignOnly() = run("HARD") { s, e, snd ->
        setLevel(s, 2); e.tick()
        assertTrue(snd.sent.isEmpty())
        now += 119_000; e.tick()
        assertTrue(snd.sent.isEmpty())
        now += 1_000; e.tick()
        assertEquals(1, snd.sent.size)
        val body = String(java.util.Base64.getDecoder().decode(snd.sent[0].line.split(":")[8]), Charsets.UTF_8)
        assertTrue(body.startsWith("MB10:SECALERT:v1:n7:"))
        assertTrue(body.endsWith(":2:0J/RgNC40LfRgNCw0Lo=:"))
    }

    @Test fun ghostHidesCallsignBlackoutKillsSignal() {
        run(effects = listOf("GHOST")) { s, e, snd ->
            setLevel(s, 2); e.tick()
            val body = String(java.util.Base64.getDecoder().decode(snd.sent[0].line.split(":")[8]), Charsets.UTF_8)
            assertTrue(body.endsWith(":3::1000000"))
        }
        run(effects = listOf("BLACKOUT")) { s, e, snd ->
            setLevel(s, 2); e.tick()
            assertTrue(snd.sent.isEmpty())
        }
    }

    @Test fun ownNodeGivesNoSignal() = run { s, e, snd ->
        val r = s.get("runner", "r1")!!
        s.put("runner", "r1", r.ver, VJ.with(r.data, "faction" to VJ.p("СБ")))
        setLevel(s, 2); e.tick()
        assertTrue(snd.sent.isEmpty())
    }

    @Test fun signalFollowsTheCurrentNodeAfterATunnel() = run { s, e, snd ->
        // игрок прошёл тоннелем в узел своей фракции (world.node): сигнала нет, хотя принят он был в узле СБ
        s.put("node", "n8", 0, VJ.obj("title" to VJ.p("Лаборатория"), "tier" to VJ.p("NIGHTMARE"), "owner_faction" to VJ.p("Корпа")))
        val d = s.get("session", "s1")!!
        val w = d.data["world"] as JsonObject
        s.put("session", "s1", d.ver, JsonObject(d.data + ("world" to JsonObject(w + ("node" to JsonPrimitive("n8"))))))
        setLevel(s, 2); e.tick()
        assertTrue(snd.sent.isEmpty())
    }

    @Test fun venueLinkOffSendsNothingUntilOn() = run { s, e, snd ->
        s.put("settings", "global", 0, VJ.obj("venue_link" to VJ.p(false)))
        setLevel(s, 2); e.tick(); now += 2_000; e.tick()
        assertTrue(snd.sent.isEmpty())
    }
}
