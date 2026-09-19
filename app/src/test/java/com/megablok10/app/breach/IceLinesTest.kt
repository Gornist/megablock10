package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class IceLinesTest {
    @Test
    fun `every tier and event has a line`() {
        assertTrue(IceLines.isComplete())
    }

    @Test
    fun `line is stable for the same seed and fits one status row`() {
        for (tier in Tier.values()) for (event in IceEvent.values()) {
            val a = IceLines.line(tier, event, Random(42))
            assertEquals(a, IceLines.line(tier, event, Random(42)))
            assertTrue("«$a» слишком длинная для строки статуса", a.length <= 60)
        }
    }
}
