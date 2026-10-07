package com.megablok10.app.voice

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Файлы голосовых: запись атомарна, чужой id не выходит из папки, сброс стирает всё. */
class VoiceStoreTest {
    @get:Rule val folder = TemporaryFolder()
    private val dir get() = folder.root.resolve("voice")
    private val store get() = VoiceStore(dir)

    @Test fun writesAndReadsBack() {
        val bytes = ByteArray(500) { it.toByte() }
        assertTrue(store.write("clip-0123456789", bytes))
        assertTrue(store.exists("clip-0123456789"))
        assertArrayEquals(bytes, store.read("clip-0123456789"))
        assertEquals(listOf("clip-0123456789.m4a"), dir.list()!!.toList())
    }

    @Test fun sameFileTwiceIsFine() {
        val bytes = ByteArray(100) { 7 }
        assertTrue(store.write("clip-0123456789", bytes))
        assertTrue(store.write("clip-0123456789", bytes))
    }

    @Test fun badIdEmptyAndOversizeAreRefused() {
        assertFalse(store.write("../../escape-attempt", ByteArray(10)))
        assertFalse(store.write("clip-0123456789", ByteArray(0)))
        assertFalse(store.write("clip-0123456789", ByteArray(VoiceLimits.MAX_AUDIO_BYTES + 1)))
        assertNull(store.read("../../escape-attempt"))
        assertFalse(folder.root.resolve("escape-attempt.m4a").exists())
    }

    @Test fun missingFileReadsAsNull() {
        assertNull(store.read("clip-0123456789"))
        assertFalse(store.exists("clip-0123456789"))
    }

    @Test fun deleteAllWipesEverything() {
        store.write("clip-0123456789", ByteArray(10) { 1 })
        store.write("clip-9876543210", ByteArray(10) { 2 })
        store.deleteAll()
        assertEquals(0, dir.list()!!.size)
    }

    @Test fun adoptTakesARecordedFile() {
        val source = folder.newFile("rec.m4a").also { it.writeBytes(ByteArray(300) { 9 }) }
        assertTrue(store.adopt("clip-0123456789", source))
        assertEquals(300, store.read("clip-0123456789")!!.size)
    }
}
