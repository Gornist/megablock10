package com.megablok10.netrun.bridge

import com.megablok10.netrun.bridge.phone.PhoneSender
import com.megablok10.netrun.bridge.phone.PhoneWire
import com.megablok10.rules.SecAlertAggregator
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/**
 * Отправка сигналов СБ, решённых `run.breach` (протокол, раздел 5, `sec_alert`; 6.6). В отличие от правила P3 ([SecAlertRule]),
 * держащего очередь в памяти, решение лежит в документе `sec_alert` и переживает рестарт Моста: правило раз в `sec_alert_tick_s`
 * просматривает документы в состоянии `pending`.
 *
 * `send_at` наступил и рубильник связи включён — сообщение фракции от «SEC//MB10» (то же, что P3: `MB10CHAT … FACTION`, тело
 * `MB10:SECALERT:v1`, `containerName` — название узла, без номера терминала) уходит телефонам `settings/sec.factions[фракция]`,
 * которые сейчас в сети; документ получает `state: sent`. После `ttl_at` — `expired` без отправки (рубильник выключен — ждёт, как P3).
 * Состояние пишется **до** отправки: сбой между ними теряет один сигнал, но не шлёт его дважды.
 *
 * Склейку «полное сообщение раз в 15 минут на узел, дальше счётчик повторов» делает [SecAlertAggregator] из `:rules`, как в приложении:
 * живёт в памяти и после рестарта начинается заново (ревизия v9 §4).
 */
class BreachAlertRule(
    private val engine: RuleEngine,
    private val store: DocStore,
    private val sender: PhoneSender,
    private val clock: () -> Long = System::currentTimeMillis,
    private val log: (String) -> Unit = { System.err.println(it) },
    /** Как выполнять блокирующую отправку; в бою — в IO-скоупе, чтобы не держать поток правил на сокетах. */
    private val dispatch: (() -> Unit) -> Unit = { it() },
) {
    private val aggregation = SecAlertAggregator()

    fun register() {
        engine.every("breach_alert_flush", "sec_alert_tick_s", 1) { flush() }
    }

    /** Один проход по документам `sec_alert`; боевой Мост зовёт его правилом [register], тесты — напрямую. */
    fun flush() {
        val now = clock()
        val linkOn = MasterOps.venueLinkOn(store)
        for (d in store.list(TYPE)) {
            if (VJ.str(d.data, "state") != "pending") continue
            when {
                VJ.lng(d.data, "ttl_at") <= now -> mark(d, "expired")
                linkOn && VJ.lng(d.data, "send_at") <= now -> send(d, now)
            }
        }
    }

    private fun mark(d: Doc, state: String): Boolean = try {
        store.put(TYPE, d.id, d.ver, VJ.with(d.data, "state" to VJ.p(state)))
        true
    } catch (e: StoreException) {
        log("breach_alert.skip id=${d.id} code=${e.code}")  // документ тем временем изменили (мастер удалил): в следующий проход
        false
    }

    private fun send(d: Doc, now: Long) {
        if (!mark(d, "sent")) return
        val faction = VJ.str(d.data, "faction").orEmpty()
        val node = VJ.str(d.data, "node").orEmpty()
        val title = VJ.str(d.data, "title") ?: node
        val keys = (((store.get(ValueOps.SETTINGS, "sec")?.data?.get("factions") as? kotlinx.serialization.json.JsonObject)?.get(faction)) as? JsonArray)
            .orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }.filter { sender.isOnline(it) }
        log("breach_alert.send id=${d.id} faction=$faction node=$node recipients=${keys.size}")
        if (keys.isEmpty()) return
        val payload = PhoneWire.encodeSecAlert(
            node, title, VJ.lng(d.data, "tier").toInt(), VJ.str(d.data, "callsign"),
            d.data["precise_at"]?.let { (it as? JsonPrimitive)?.takeIf { p -> !p.isString }?.content?.toLongOrNull() },
        )
        val body = aggregation.body(node, title, payload, now, SecAlertAggregator.WINDOW_MS)
        val line = PhoneWire.encodeFactionChat(SecAlertRule.SYSTEM_PUBKEY, SecAlertRule.SYSTEM_CALLSIGN, faction, now, body)
        for (k in keys) {
            dispatch {
                val out = sender.send(k, line)
                log("breach_alert.sent faction=$faction to=${k.take(8)} outcome=${out.name}")
            }
        }
    }

    companion object {
        /** Тип документа решённого сигнала СБ. */
        const val TYPE = "sec_alert"
    }
}
