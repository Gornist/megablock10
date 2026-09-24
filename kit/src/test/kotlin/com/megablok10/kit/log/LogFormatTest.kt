package com.megablok10.kit.log

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LogFormatTest {
    @Test
    fun `поля через пробел, null пропускается`() {
        assertEquals("send.outcome to=ab12 ms=41", LogFormat.event("send.outcome", arrayOf("to" to "ab12", "skip" to null, "ms" to 41)))
    }

    @Test
    fun `без полей — только имя`() {
        assertEquals("chat.stop", LogFormat.event("chat.stop", emptyArray()))
    }

    @Test
    fun `значения с пробелами, кавычками, переводами строк и пустые — в кавычках`() {
        val line = LogFormat.event("x", arrayOf("a" to "два слова", "b" to "с \"кавычкой\"", "c" to "стр\nока", "d" to ""))
        assertEquals("x a=\"два слова\" b=\"с 'кавычкой'\" c=\"стр ока\" d=\"\"", line)
    }

    @Test
    fun `shortKey — последние 8 букв и цифр, пустое — дефис`() {
        assertEquals("-", shortKey(null))
        assertEquals("-", shortKey(""))
        assertEquals("CDEFGH12", shortKey("MFkw+EwYH/KoZIzj0CAQYI+abCDEFGH12=="))
    }

    @Test
    fun `RecordingLog пишет в том же формате`() {
        val log = RecordingLog()
        log.event("Tag", "a.b", "k" to 1)
        log.warnEvent("Tag", "c.d")
        assertEquals(listOf("I/Tag a.b k=1", "W/Tag c.d"), log.all)
        assertTrue(log.has("W/Tag c.d"))
        assertFalse(log.has("e.f"))
    }
}
