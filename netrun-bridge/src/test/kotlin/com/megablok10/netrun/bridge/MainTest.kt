package com.megablok10.netrun.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MainTest {
    @get:Rule val tmp = TemporaryFolder()
    private val env = mapOf("NETRUN_KEY_WORLD" to "w", "NETRUN_KEY_MASTER" to "m", "NETRUN_KEY_TEST" to "t")

    @Test fun parsesArgs() {
        val o = parseLaunch(listOf("--port", "0", "--line-port", "0", "--db", "x.db", "--test"), env)
        assertEquals(0, o.port)
        assertEquals("x.db", o.db)
        assertTrue(o.config.testMode)
        assertEquals("w", o.config.roleKeys["world"])
    }

    @Test(expected = IllegalArgumentException::class) fun needsKeys() {
        parseLaunch(emptyList(), emptyMap())
    }

    @Test(expected = IllegalArgumentException::class) fun testModeNeedsTestKey() {
        parseLaunch(listOf("--test"), mapOf("NETRUN_KEY_WORLD" to "w", "NETRUN_KEY_MASTER" to "m"))
    }

    @Test fun appStartsWithDefaultSettings() {
        val db = tmp.root.resolve("m.db").path
        BridgeApp(parseLaunch(listOf("--port", "0", "--line-port", "0", "--db", db), env)).use { app ->
            app.start()
            val s = app.store.get("settings", "global")
            assertNotNull(s)
            assertEquals(120L, VJ.lng(s!!.data, "confirm_timeout_s"))
            // ключ мира: создан при старте, лежит рядом с базой, публичная часть — в settings
            assertEquals(app.worldKey.publicB64, VJ.str(s.data, "world_pub"))
            assertTrue(java.io.File("$db.worldkey").exists())
        }
        // второй старт на той же базе настройки не затирает
        BridgeApp(parseLaunch(listOf("--port", "0", "--line-port", "0", "--db", db), env)).use { app ->
            assertEquals(1L, app.store.get("settings", "global")!!.ver)
            assertEquals(VJ.str(app.store.get("settings", "global")!!.data, "world_pub"), app.worldKey.publicB64) // тот же ключ
        }
    }
}
