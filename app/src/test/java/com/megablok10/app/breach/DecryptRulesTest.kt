package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DecryptRulesTest {
    private fun daemon(id: String, tier: Tier, effect: DaemonEffect) = Daemon(id, id, listOf("1C", "55"), tier, effect)

    @Test
    fun `no decrypter means the shard cannot be opened`() {
        assertNull(DecryptRules.bestDecrypter(listOf(daemon("a", Tier.NIGHTMARE, DaemonEffect.GHOST)), shardTier = 1))
        assertNull(DecryptRules.bestDecrypter(emptyList(), shardTier = 1))
    }

    @Test
    fun `decrypter must cover the shard tier and the weakest sufficient one is chosen`() {
        val t1 = daemon("t1", Tier.BASE, DaemonEffect.DECRYPT)
        val t2 = daemon("t2", Tier.HARD, DaemonEffect.DECRYPT)
        val t3 = daemon("t3", Tier.NIGHTMARE, DaemonEffect.DECRYPT)
        assertNull(DecryptRules.bestDecrypter(listOf(t1), shardTier = 2))
        assertEquals(t2, DecryptRules.bestDecrypter(listOf(t3, t2, t1), shardTier = 2))
        assertEquals(t3, DecryptRules.bestDecrypter(listOf(t3, t1), shardTier = 3))
    }

    @Test
    fun `garble hides the text but keeps its shape and is stable`() {
        val body = "Очень секретный текст\nвторая строка"
        val g = DecryptRules.garble(body, seed = 7)
        assertEquals(body.length, g.length)
        assertEquals(g, DecryptRules.garble(body, seed = 7))
        assertNotEquals(g, DecryptRules.garble(body, seed = 8))
        assertTrue(g.none { it in 'а'..'я' || it in 'А'..'Я' })
        assertEquals(body.indexOf('\n'), g.indexOf('\n'))
    }

    @Test
    fun `miner adds eddies scaled by tier`() {
        assertTrue(ContainerEddies.minerBonus(Tier.BASE) < ContainerEddies.minerBonus(Tier.HARD))
        assertTrue(ContainerEddies.minerBonus(Tier.HARD) < ContainerEddies.minerBonus(Tier.NIGHTMARE))
    }
}
