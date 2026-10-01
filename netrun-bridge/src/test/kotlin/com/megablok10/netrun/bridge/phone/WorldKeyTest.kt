package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.crypto.Ecdsa
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WorldKeyTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun createdOnFirstStartAndReadBackUnchanged() {
        val file = tmp.root.resolve("m.db.worldkey")
        val first = WorldKey.loadOrCreate(file)
        assertTrue(file.exists())
        val second = WorldKey.loadOrCreate(file)
        assertEquals(first.publicB64, second.publicB64)
        val data = "проверка".toByteArray()
        assertTrue(Ecdsa.verify(first.publicB64, data, second.sign(data))) // тот же закрытый ключ
    }

    @Test fun fileNextToDbAndNoneForMemory() {
        assertEquals("a/m.db.worldkey", WorldKey.fileFor("a/m.db")!!.path)
        assertEquals(null, WorldKey.fileFor(":memory:"))
    }

    @Test(expected = IllegalArgumentException::class) fun brokenFileIsAnError() {
        val file = tmp.root.resolve("bad.worldkey")
        file.writeText("только одна строка\n")
        WorldKey.loadOrCreate(file)
    }
}
