package com.megablok10.app.items

import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.Tier
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ItemPayloadTest {
    private val shard = Mb10Qr.Shard(
        id = "shard:arasaka-404#0", decryptAction = true, tier = 2, valueHint = "ценность: очень высокая",
        title = "Схемы «Кибер-тела»", meta = "Арасака · секция 7", body = "Строка 1\nСтрока | с разделителем : и двоеточием", moneyAmount = 0, decrypted = false
    )

    @Test
    fun `shard survives a round trip including the decrypted flag`() {
        assertEquals(shard, ItemPayload.decodeShard(ItemPayload.encodeShard(shard)))
        val opened = shard.copy(decrypted = true)
        assertEquals(opened, ItemPayload.decodeShard(ItemPayload.encodeShard(opened)))
    }

    @Test
    fun `daemon survives a round trip`() {
        val daemon = Daemon("daemon:x#1", "Blackout «Тень»", listOf("1C", "BD", "55"), Tier.HARD, DaemonEffect.BLACKOUT)
        assertEquals(daemon, ItemPayload.decodeDaemon(ItemPayload.encodeDaemon(daemon)))
    }

    @Test
    fun `broken or foreign payloads decode to null instead of crashing`() {
        assertNull(ItemPayload.decodeShard("DAEMON|a|b|c|d|e"))
        assertNull(ItemPayload.decodeDaemon("SHARD|1"))
        assertNull(ItemPayload.decodeDaemon("DAEMON|id|!!!|1C|1|NO_SUCH_EFFECT"))
        assertNull(ItemPayload.decodeShard(""))
    }

    @Test
    fun `item card encodes to a chat body and back, keeping the signed payload bytes`() {
        val payload = ItemPayload.encodeShard(shard)
        val card = Mb10Qr.ItemTransfer("item-1", "PK_A", ItemKind.SHARD, payload, "SIG")
        val decoded = Mb10QrCodec.decode(Mb10QrCodec.encodeItemTransfer(card))
        assertNotNull(decoded)
        assertEquals(card, decoded)
        assertEquals(
            String(Mb10QrCodec.itemTransferSignaturePayload("item-1", "PK_A", ItemKind.SHARD, payload)),
            "item-1|PK_A|SHARD|$payload"
        )
    }
}
