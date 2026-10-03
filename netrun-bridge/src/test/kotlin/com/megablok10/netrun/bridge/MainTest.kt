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
            // два рычага Soft ICE (D1): пауза нетраннера 3 минуты, локдаун узла 10 минут
            assertEquals(180L, VJ.lng(s.data, "soft_ice_reentry_pause_s"))
            assertEquals(600L, VJ.lng(s.data, "node_lockdown_s"))
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

    @Test fun seedNeedsTestModeAndIsIdempotent() {
        val bad = runCatching { parseLaunch(listOf("--seed", "s.json"), env) }
        assertTrue(bad.exceptionOrNull() is IllegalArgumentException)
        assertEquals("s.json", parseLaunch(listOf("--test", "--seed", "s.json"), env).seed)

        val db = tmp.root.resolve("s.db").path
        val json = """{"node": {"node_07": {"eddies": 5}}, "settings": {"global": {"auditor_period_s": 2}}}"""
        BridgeApp(parseLaunch(listOf("--port", "0", "--line-port", "0", "--db", db), env)).use { app ->
            assertEquals(2, seedDocs(app.store, json))
            assertEquals(5L, VJ.lng(app.store.get("node", "node_07")!!.data, "eddies"))
            // настройки дополнены, world_pub на месте
            val g = app.store.get("settings", "global")!!
            assertEquals(2L, VJ.lng(g.data, "auditor_period_s"))
            assertEquals(app.worldKey.publicB64, VJ.str(g.data, "world_pub"))
            // существующий узел не затирается
            val ver = app.store.get("node", "node_07")!!.ver
            seedDocs(app.store, json)
            assertEquals(ver, app.store.get("node", "node_07")!!.ver)
        }
    }

    @Test fun phoneAddressNeedsTestModeAndKeepsEqualsOfKey() {
        val bad = runCatching { parseLaunch(listOf("--phone", "127.0.0.1:4000=KEY"), env) }
        assertTrue(bad.exceptionOrNull() is IllegalArgumentException)
        val o = parseLaunch(listOf("--test", "--phone", "127.0.0.1:4000=MFkw+/Ew==", "--phone", "10.0.0.5:5000=K2"), env)
        assertEquals(listOf(StaticPhone("127.0.0.1", 4000, "MFkw+/Ew=="), StaticPhone("10.0.0.5", 5000, "K2")), o.phones)
        for (spec in listOf("127.0.0.1=KEY", "127.0.0.1:x=KEY", "127.0.0.1:4000=", "127.0.0.1:4000")) {
            assertTrue(spec, runCatching { parseLaunch(listOf("--test", "--phone", spec), env) }.exceptionOrNull() is IllegalArgumentException)
        }
    }

    @Test fun collectorIsOptionalAndTakesSecretFromEnvironment() {
        assertEquals(null, parseLaunch(emptyList(), env).collector)
        val o = parseLaunch(listOf("--collector", "http://10.10.0.10:2517/"), env + ("NETRUN_COLLECTOR_SECRET" to "game"))
        assertEquals("http://10.10.0.10:2517", o.collector!!.baseUrl)
        assertEquals("game", o.collector.secret)
        // пустой секрет — как отсутствующий: коллектор без GAME_SECRET заголовка не ждёт
        assertEquals(null, parseLaunch(listOf("--collector", "http://c:1"), env + ("NETRUN_COLLECTOR_SECRET" to " ")).collector!!.secret)
    }

    @Test fun collectorSecretIsTrimmedAndOnlyPrintableAsciiStartsTheBridge() {
        // перевод строки в конце (секрет из файла или echo) и пробелы по краям срезаются
        val trimmed = parseLaunch(listOf("--collector", "http://c:1"), env + ("NETRUN_COLLECTOR_SECRET" to " game\n"))
        assertEquals("game", trimmed.collector!!.secret)
        // всё прочее для HTTP-заголовка не годится: JDK бросил бы исключение с секретом в тексте. Старт отказывает, значения в ошибке нет.
        for (secret in listOf("tok\nQQMARKER", "tok\r\nQQMARKER", "ЗАПРЕТQQMARKER", "tok\u0100QQMARKER", "tok\u0000QQMARKER", "tok\tQQMARKER")) {
            val e = runCatching { parseLaunch(listOf("--collector", "http://c:1"), env + ("NETRUN_COLLECTOR_SECRET" to secret)) }.exceptionOrNull()
            assertTrue(secret, e is IllegalArgumentException)
            val message = e!!.message!!
            assertTrue(message, message.contains("NETRUN_COLLECTOR_SECRET"))
            assertTrue(message, !message.contains("QQMARKER") && !message.contains("tok") && !message.contains("ЗАПРЕТ"))
        }
        // без --collector секрет не используется и старт не ломает
        assertEquals(null, parseLaunch(emptyList(), env + ("NETRUN_COLLECTOR_SECRET" to "tok\nx")).collector)
    }

    @Test fun collectorNeedsHttpAddress() {
        for (bad in listOf("10.10.0.10:2517", "ftp://x", "")) {
            assertTrue(bad, runCatching { parseLaunch(listOf("--collector", bad), env) }.exceptionOrNull() is IllegalArgumentException)
        }
    }
}
