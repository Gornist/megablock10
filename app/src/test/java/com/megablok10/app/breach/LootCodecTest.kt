package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LootCodecTest {

    @Test
    fun `shard loot round-trips with punctuation and cyrillic in every free-text field`() {
        val raw = LootCodec.encodeShard(
            title = "Служебный лог: клиника",
            meta = "получен 21:02 · клиника, уровень доступа 2",
            body = "«...партия С-9: брак клапана...»",
            valueHint = "ценный тех. документ",
            decryptAction = true,
            moneyAmount = 250
        )
        assertEquals(
            LootCodec.Loot.ShardLoot(
                title = "Служебный лог: клиника",
                meta = "получен 21:02 · клиника, уровень доступа 2",
                body = "«...партия С-9: брак клапана...»",
                valueHint = "ценный тех. документ",
                decryptAction = true,
                moneyAmount = 250
            ),
            LootCodec.decode(raw)
        )
    }

    @Test
    fun `daemon loot round-trips with a multi-code sequence`() {
        val raw = LootCodec.encodeDaemon(name = "Химера", sequence = listOf("1C", "BD", "E9"), tier = Tier.HARD, effect = DaemonEffect.GHOST)
        assertEquals(
            LootCodec.Loot.DaemonLoot(name = "Химера", sequence = listOf("1C", "BD", "E9"), tier = Tier.HARD, effect = DaemonEffect.GHOST),
            LootCodec.decode(raw)
        )
    }

    @Test
    fun `unknown type tag decodes to null`() {
        assertNull(LootCodec.decode("BOGUS|whatever"))
    }

    @Test
    fun `truncated shard payload decodes to null instead of throwing`() {
        assertNull(LootCodec.decode("SHARD|onlyonefield"))
    }

    @Test
    fun `garbage base64 in a shard field decodes to null instead of throwing`() {
        assertNull(LootCodec.decode("SHARD|not-valid-base64!!!|b|c|d|1|0"))
    }
}
