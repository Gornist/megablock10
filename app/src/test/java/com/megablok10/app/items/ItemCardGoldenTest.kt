package com.megablok10.app.items

import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.SecAlertStore
import com.megablok10.app.breach.Tier
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Эталонные строки карточек предметов (M1): байты полезной нагрузки и карточки не должны меняться при переносе правил
 * в общий модуль. Значения получены до переноса и зафиксированы здесь.
 */
class ItemCardGoldenTest {
    private val shard = Mb10Qr.Shard(
        id = "shard:a#0", decryptAction = true, tier = 2, valueHint = "ценность", title = "Схемы", meta = "Арасака",
        body = "Строка 1\nстрока 2", moneyAmount = 0, decrypted = false
    )
    private val daemon = Daemon("daemon:x#1", "Тень", listOf("1C", "BD", "55"), Tier.HARD, DaemonEffect.BLACKOUT)

    private val shardPayload =
        "SHARD|shard:a#0|1|2|0YbQtdC90L3QvtGB0YLRjA==|0KHRhdC10LzRiw==|0JDRgNCw0YHQsNC60LA=|0KHRgtGA0L7QutCwIDEK0YHRgtGA0L7QutCwIDI=|0|0"
    private val daemonPayload = "DAEMON|daemon:x#1|0KLQtdC90Yw=|1C,BD,55|2|BLACKOUT"

    @Test
    fun `shard payload bytes are fixed`() {
        assertEquals(shardPayload, ItemPayload.encodeShard(shard))
        assertEquals(shard, ItemPayload.decodeShard(shardPayload))
    }

    @Test
    fun `daemon payload bytes are fixed`() {
        assertEquals(daemonPayload, ItemPayload.encodeDaemon(daemon))
        assertEquals(daemon, ItemPayload.decodeDaemon(daemonPayload))
    }

    @Test
    fun `signed part of the item card is fixed`() {
        assertEquals(
            "ITEM2|i1|PK_A|PK_B|SHARD|$shardPayload",
            String(Mb10QrCodec.itemTransferSignaturePayload("i1", "PK_A", "PK_B", ItemKind.SHARD, shardPayload))
        )
        assertEquals(
            "ITEM2|i2|PK_A|PK_B|DAEMON|$daemonPayload",
            String(Mb10QrCodec.itemTransferSignaturePayload("i2", "PK_A", "PK_B", ItemKind.DAEMON, daemonPayload))
        )
    }

    @Test
    fun `whole item card encodes to the same body and decodes back`() {
        val card = Mb10Qr.ItemTransfer("i1", "PK_A", "PK_B", ItemKind.SHARD, shardPayload, "SIG")
        val body = Mb10QrCodec.encodeItemTransfer(card)
        assertEquals(card, Mb10QrCodec.decode(body))
        assertEquals(
            "MB10:ITEM:v2:i1:PK_A:PK_B:SHARD:U0hBUkR8c2hhcmQ6YSMwfDF8MnwwWWJRdGRDOTBMM1F2dEdCMFlMUmpBPT18MEtIUmhkQzEwTHpSaXc9PXwwSkRSZ05DdzBZSFFzTkM2MExBPXwwS0hSZ3RHQTBMN1F1dEN3SURFSzBZSFJndEdBMEw3UXV0Q3dJREk9fDB8MA==:SIG",
            body
        )
    }

    @Test
    fun `labels and enums are fixed`() {
        assertEquals(listOf("BASE", "HARD", "NIGHTMARE"), Tier.entries.map { it.name })
        assertEquals(
            listOf("EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"),
            DaemonEffect.entries.map { it.name }
        )
        val plan = SecAlertStore.decide("A", "B", Tier.NIGHTMARE, com.megablok10.app.breach.BreachOutcome.SUCCESS, setOf(DaemonEffect.TIMESKEW), 100L)
        assertEquals(100L + 10 * 60_000L, plan?.sendAt)
        assertEquals(true, plan?.revealCallsign)
        assertEquals(true, plan?.revealPreciseTime)
    }
}
