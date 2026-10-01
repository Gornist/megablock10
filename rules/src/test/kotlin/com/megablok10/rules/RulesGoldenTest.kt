package com.megablok10.rules

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Эталонные строки и правила без Android: те же значения, что в тесте приложения (ItemCardGoldenTest). */
class RulesGoldenTest {
    private val shard = ShardPayload(
        id = "shard:a#0", decryptAction = true, tier = 2, valueHint = "ценность", title = "Схемы", meta = "Арасака",
        body = "Строка 1\nстрока 2", moneyAmount = 0, decrypted = false
    )
    private val daemon = Daemon("daemon:x#1", "Тень", listOf("1C", "BD", "55"), Tier.HARD, DaemonEffect.BLACKOUT)

    private val shardPayload =
        "SHARD|shard:a#0|1|2|0YbQtdC90L3QvtGB0YLRjA==|0KHRhdC10LzRiw==|0JDRgNCw0YHQsNC60LA=|0KHRgtGA0L7QutCwIDEK0YHRgtGA0L7QutCwIDI=|0|0"

    @Test
    fun `shard and daemon payload bytes are fixed`() {
        assertEquals(shardPayload, ItemPayloadCodec.encodeShard(shard))
        assertEquals(shard, ItemPayloadCodec.decodeShard(shardPayload))
        val daemonPayload = "DAEMON|daemon:x#1|0KLQtdC90Yw=|1C,BD,55|2|BLACKOUT"
        assertEquals(daemonPayload, ItemPayloadCodec.encodeDaemon(daemon))
        assertEquals(daemon, ItemPayloadCodec.decodeDaemon(daemonPayload))
    }

    @Test
    fun `foreign payloads decode to null`() {
        assertNull(ItemPayloadCodec.decodeShard("DAEMON|a|b|c|d|e"))
        assertNull(ItemPayloadCodec.decodeDaemon("DAEMON|id|!!!|1C|1|NO_SUCH_EFFECT"))
        assertNull(ItemPayloadCodec.decodeShard(""))
    }

    @Test
    fun `tiers and effects keep names and order`() {
        assertEquals(listOf(1, 2, 3), Tier.entries.map { it.level })
        assertEquals(Tier.BASE, Tier.fromLevel(99))
        assertEquals(8, DaemonEffect.entries.size)
    }

    @Test
    fun `alert rules`() {
        assertNull(SecAlertRules.decide("A", "A", Tier.NIGHTMARE, BreachOutcome.SUCCESS, emptySet(), 0))
        assertNull(SecAlertRules.decide("A", "B", Tier.BASE, BreachOutcome.FAIL, emptySet(), 0))
        assertNull(SecAlertRules.decide("A", "B", Tier.HARD, BreachOutcome.SUCCESS, setOf(DaemonEffect.BLACKOUT), 0))
        val plan = SecAlertRules.decide("A", "B", Tier.HARD, BreachOutcome.SUCCESS, setOf(DaemonEffect.TIMESKEW, DaemonEffect.GHOST), 100)
        assertEquals(100L + 12 * 60_000L, plan?.sendAt)
        assertEquals(false, plan?.revealCallsign)
        assertEquals(false, plan?.revealPreciseTime)
        assertEquals(0L, SecAlertRules.decide("A", "B", Tier.NIGHTMARE, BreachOutcome.PARTIAL, emptySet(), 0)?.sendAt)
    }
}
