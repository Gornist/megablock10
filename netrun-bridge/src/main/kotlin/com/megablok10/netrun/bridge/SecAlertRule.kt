package com.megablok10.netrun.bridge

import com.megablok10.netrun.bridge.phone.PhoneSender
import com.megablok10.netrun.bridge.phone.PhoneWire
import com.megablok10.rules.BreachOutcome
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.SecAlertRules
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Правило P3: сигнал СБ с номером терминала (`docs/netrun.md`, «Обнаружение и сигнал СБ»).
 *
 * Сервер мира пишет `session.world.trace_level` (число `TraceMeter.Level`: 2 = TRACE, 3 = LOCKDOWN). На уровне TRACE и выше правило
 * решает через общий [SecAlertRules.decide] (свой узел, BLACKOUT, задержка по тиру, TIMESKEW, GHOST) и шлёт телефонам фракции-владельца
 * узла то же сообщение фракции от «SEC//MB10», что и [SecAlertStore] приложения (`MB10CHAT … FACTION`, тело `MB10:SECALERT:v1`);
 * формат и версии не меняются. Номер терминала едет в `containerName` («<узел> · терминал <id>»), как и название контейнера на телефоне.
 *
 * Один раз на сессию и уровень (память Моста: после его рестарта уровень, уже бывший в документе, не шлётся заново, пока он не вырос
 * в новую правку сервера). Рубильник связи ([MasterOps.venueLinkOn]) выключен — не шлём и не запоминаем, пока он выключен, но
 * отложенное по задержке не отправляется до его включения (доживёт до ttl 30 мин, как в приложении).
 *
 * Адресаты — `settings/sec`: `{"factions": {"<фракция>": ["<ключ телефона>", …]}, "default_faction": "<фракция>"}`. Фракция-владелец —
 * `node.owner_faction`, иначе `settings/sec.default_faction`. Ключи телефонов Мост иначе не знает (в строках фракция не едет), запрос
 * к коллектору — в отчёте P3. Опционально `session.world.effects` — имена [DaemonEffect] активных демонов (GHOST, TIMESKEW, BLACKOUT).
 */
class SecAlertRule(
    private val engine: RuleEngine,
    private val store: DocStore,
    private val sender: PhoneSender,
    private val clock: () -> Long = System::currentTimeMillis,
    private val log: (String) -> Unit = { System.err.println(it) },
    /** Как выполнять блокирующую отправку; в бою — в IO-скоупе, чтобы не держать поток правил на сокетах. */
    private val dispatch: (() -> Unit) -> Unit = { it() },
) {
    private class Pending(val sendAt: Long, val ttl: Long, val faction: String, val line: String, val recipients: List<String>)

    private val sent = HashSet<String>()
    private val pending = ArrayList<Pending>()

    fun register() {
        engine.onChange("sec_alert", ValueOps.SESSION) { _, c -> if (!c.deleted) onSession(c.doc) }
        engine.every("sec_alert_flush", "sec_alert_tick_s", 1) { flush() }
    }

    private fun onSession(d: Doc) {
        val world = d.data["world"] as? JsonObject ?: return
        val level = (world["trace_level"] as? JsonPrimitive)?.content?.toIntOrNull() ?: return
        val eligible = level >= TRACE_LEVEL && VJ.str(d.data, "state") == "active" && MasterOps.venueLinkOn(store)
        if (!eligible || !sent.add("${d.id}:$level")) return
        val node = VJ.str(d.data, "node").orEmpty()
        val nodeDoc = store.get(ValueOps.NODE, node)
        val sec = store.get(ValueOps.SETTINGS, "sec")?.data
        val owner = nodeDoc?.let { VJ.str(it.data, "owner_faction") }?.takeIf { it.isNotBlank() } ?: sec?.let { VJ.str(it, "default_faction") }.orEmpty()
        val runner = store.get(ValueOps.RUNNER, VJ.str(d.data, "runner").orEmpty())
        val intruderFaction = runner?.let { VJ.str(it.data, "faction") }.orEmpty()
        val tier = runCatching { Tier.valueOf(nodeDoc?.let { VJ.str(it.data, "tier") }.orEmpty()) }.getOrDefault(Tier.BASE)
        val effects = (world["effects"] as? JsonArray).orEmpty().mapNotNull { e -> DaemonEffect.entries.firstOrNull { it.name == (e as? JsonPrimitive)?.content } }.toSet()
        val now = clock()
        val plan = SecAlertRules.decide(owner, intruderFaction, tier, BreachOutcome.SUCCESS, effects, now)
        log("sec_alert.decide session=${d.id} level=$level node=$node owner=$owner suppressed=${plan == null}")
        if (plan == null) return
        val terminal = VJ.str(d.data, "terminal").orEmpty()
        val title = nodeDoc?.let { VJ.str(it.data, "title") }?.takeIf { it.isNotBlank() } ?: node
        val body = PhoneWire.encodeSecAlert(
            node, "$title · терминал $terminal", tier.level,
            if (plan.revealCallsign) VJ.str(d.data, "callsign") else null,
            if (plan.revealPreciseTime) now else null,
        )
        val line = PhoneWire.encodeFactionChat(SYSTEM_PUBKEY, SYSTEM_CALLSIGN, owner, now, body)
        val keys = (((sec?.get("factions") as? JsonObject)?.get(owner)) as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }
        pending += Pending(plan.sendAt, now + TTL_MS, owner, line, keys)
        flush()
    }

    private fun flush() {
        val now = clock()
        pending.removeAll { it.ttl <= now }
        if (!MasterOps.venueLinkOn(store)) return
        val due = pending.filter { it.sendAt <= now }
        pending.removeAll(due.toSet())
        for (p in due) for (k in p.recipients) {
            if (!sender.isOnline(k)) continue
            dispatch {
                val out = sender.send(k, p.line)
                log("sec_alert.send faction=${p.faction} to=${k.take(8)} outcome=${out.name}")
            }
        }
    }

    companion object {
        const val TRACE_LEVEL = 2
        const val SYSTEM_PUBKEY = "SEC-SYSTEM"
        const val SYSTEM_CALLSIGN = "SEC//MB10"
        private const val TTL_MS = 30 * 60_000L
    }
}
