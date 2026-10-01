package com.megablok10.netrun.bridge

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DocStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private var now = 1000L
    private fun obj(vararg p: Pair<String, Long>) = JsonObject(p.associate { it.first to JsonPrimitive(it.second) })
    private fun open(path: String = tmp.root.resolve("b.db").path) = DocStore.open(path) { now++ }

    private fun code(block: () -> Unit): String? = try { block(); null } catch (e: StoreException) { e.code }

    @Test fun createReadAndVersionIncrement() {
        open().use { s ->
            val d = s.put("node", "node_07", 0, obj("a" to 1))
            assertEquals(1L, d.ver)
            assertEquals(d.created, d.updated)
            val d2 = s.put("node", "node_07", 1, obj("a" to 2))
            assertEquals(2L, d2.ver)
            assertEquals(d.created, d2.created)
            assertTrue(d2.updated > d.updated)
            assertEquals(d2, s.get("node", "node_07"))
            assertEquals(listOf(d2), s.list("node"))
        }
    }

    @Test fun versionConflictCarriesCurrentDoc() {
        open().use { s ->
            s.put("node", "n", 0, obj())
            s.put("node", "n", 1, obj("x" to 1))
            try { s.put("node", "n", 1, obj("x" to 2)); fail() } catch (e: StoreException) {
                assertEquals("version_conflict", e.code)
                assertEquals(2L, e.current?.ver)
            }
            assertEquals("exists", code { s.put("node", "n", 0, obj()) })
            assertEquals("not_found", code { s.put("node", "zz", 5, obj()) })
            assertEquals("version_conflict", code { s.delete("node", "n", 1) })
            assertEquals(2L, s.seq)
        }
    }

    @Test fun invalidKeysRejected() {
        open().use { s ->
            assertEquals("bad_request", code { s.put("Node", "n", 0, obj()) })
            assertEquals("bad_request", code { s.put("node", "a b", 0, obj()) })
        }
    }

    @Test fun restartKeepsEverythingIncludingSeq() {
        val path = tmp.root.resolve("r.db").path
        open(path).use { s ->
            s.put("node", "n", 0, obj("a" to 1))
            s.put("node", "n", 1, obj("a" to 2))
            s.put("item", "i", 0, obj())
            s.delete("item", "i", 1)
        }
        open(path).use { s ->
            assertEquals(4L, s.seq)
            val d = s.get("node", "n")!!
            assertEquals(2L, d.ver)
            assertEquals(obj("a" to 2), d.data)
            assertNull(s.get("item", "i"))
            s.put("x", "y", 0, obj()); assertEquals(5L, s.seq)
        }
    }

    @Test fun transactionIsAtomicOnFailure() {
        open().use { s ->
            s.put("item", "i", 0, obj("o" to 1))
            val seqBefore = s.seq
            val c = code {
                s.transaction { tx ->
                    tx.put("item", "i", 1, obj("o" to 2))
                    tx.put("deck", "d", 0, obj())
                    tx.put("node", "n", 7, obj()) // нет такого документа — откат всего
                }
            }
            assertEquals("not_found", c)
            assertEquals(seqBefore, s.seq)
            assertEquals(1L, s.get("item", "i")!!.ver)
            assertNull(s.get("deck", "d"))
        }
        // и после перезапуска половины нет
    }

    @Test fun failedTransactionNotPersisted() {
        val path = tmp.root.resolve("f.db").path
        open(path).use { s ->
            s.put("item", "i", 0, obj())
            code { s.transaction { it.put("deck", "d", 0, obj()); throw StoreException("boom", "x") } }
        }
        open(path).use { s ->
            assertNull(s.get("deck", "d"))
            assertEquals(1L, s.seq)
        }
    }

    @Test fun sqliteFailureRollsBackAndLeavesMemoryUntouched() {
        val path = tmp.root.resolve("s.db").path
        open(path).use { s ->
            s.put("item", "i", 0, obj("o" to 1))
            // ломаем таблицу извне: следующий коммит упадёт на второй записи
            java.sql.DriverManager.getConnection("jdbc:sqlite:$path").use {
                it.createStatement().execute("CREATE TRIGGER boom BEFORE INSERT ON docs WHEN NEW.type='deck' BEGIN SELECT RAISE(ABORT,'нет'); END")
            }
            val c = code { s.transaction { it.put("item", "i", 1, obj("o" to 2)); it.put("deck", "d", 0, obj()) } }
            assertEquals("internal", c)
            assertEquals(1L, s.get("item", "i")!!.ver)
            assertNull(s.get("deck", "d"))
            assertEquals(1L, s.seq)
        }
        open(path).use { s ->
            assertEquals(1L, s.get("item", "i")!!.ver)
            assertNull(s.get("deck", "d"))
        }
    }

    @Test fun oneTransactionOneSeqAndListenerSeesBatch() {
        open().use { s ->
            val got = ArrayList<List<Change>>()
            s.addListener { got.add(it) }
            s.put("item", "i", 0, obj())
            s.transaction { tx ->
                tx.put("item", "i", 1, obj("o" to 1))
                tx.put("deck", "d", 0, obj())
                tx.delete("item", "i", 2) // читает собственную запись
            }
            assertEquals(2L, s.seq)
            assertEquals(2, got.size)
            val batch = got[1]
            assertEquals(listOf(2L, 2L), batch.map { it.seq })
            assertEquals(listOf(false, true), batch.map { it.last })
            assertEquals(listOf(true, false), batch.map { it.deleted })
            assertNull(s.get("item", "i"))
        }
    }

    @Test fun snapshotFiltersTypes() {
        open().use { s ->
            s.put("node", "b", 0, obj()); s.put("node", "a", 0, obj()); s.put("item", "i", 0, obj())
            val (seq, docs) = s.snapshot(setOf("node"))
            assertEquals(3L, seq)
            assertEquals(listOf("a", "b"), docs.map { it.id })
        }
    }
}
