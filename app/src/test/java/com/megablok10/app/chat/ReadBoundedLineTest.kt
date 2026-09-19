package com.megablok10.app.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream

class ReadBoundedLineTest {
    private fun read(text: String, max: Int = 100) = readBoundedLine(ByteArrayInputStream(text.toByteArray(Charsets.UTF_8)), max)

    @Test
    fun `reads a normal line up to the newline`() = assertEquals("MB10CHAT:v1", read("MB10CHAT:v1\nignored"))

    @Test
    fun `strips a trailing carriage return`() = assertEquals("abc", read("abc\r\n"))

    @Test
    fun `line without a newline is returned when the stream ends`() = assertEquals("abc", read("abc"))

    @Test
    fun `empty stream gives null`() = assertNull(read(""))

    @Test
    fun `line longer than the limit is dropped instead of buffered`() = assertNull(read("x".repeat(200) + "\n", max = 100))

    @Test
    fun `cyrillic survives the utf8 decoding`() = assertEquals("привет", read("привет\n"))
}
