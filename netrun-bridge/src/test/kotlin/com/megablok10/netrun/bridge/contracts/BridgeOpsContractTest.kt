package com.megablok10.netrun.bridge.contracts

import com.megablok10.netrun.bridge.Caller
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.MasterOps
import com.megablok10.netrun.bridge.OpRouter
import com.megablok10.netrun.bridge.Role
import com.megablok10.netrun.bridge.StoreException
import com.megablok10.netrun.bridge.TerminalOps
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.ValueOps
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Операции Моста `op.take_from_node`, `op.give_item`, `run.breach` против `bridge-ops.json` (формат — `_about` в файле; близнец — GDScript-фальшь
 * `netrun/tests/bridge_ops_contract_test.gd`). Каждый случай — свежее хранилище в памяти, часы идут от `now_ms` по +1 мс за вызов.
 * Документы кладутся по порядку, `ver` документа = его номер в списке с 1 (создание + `n-1` перезаписей теми же данными).
 * Ошибка: `err.doc` — то, что Мост кладёт в ответ (`StoreException.current` в виде `VJ.docJson`).
 */
class BridgeOpsContractTest {
    private val vectors = ContractVectors.load("bridge-ops.json").list("cases")

    /**
     * Расхождения Мост ↔ вектор, найденные этим тестом: имя случая → причина. Для них тест требует, чтобы расхождение ещё было
     * (исправили Мост — случай выйдет из списка). Пока пусто.
     */
    private val knownDivergences: Map<String, String> = emptyMap()

    @Test fun takeFromNode() = runGroup("op.take_from_node")

    @Test fun giveItem() = runGroup("op.give_item")

    @Test fun runBreach() = runGroup("run.breach")

    private fun runGroup(op: String) {
        val cases = vectors.filter { it.obj("request").str("op") == op }
        assertTrue("нет случаев для $op", cases.isNotEmpty())
        val problems = ArrayList<String>()
        for (c in cases) {
            val name = c.str("name")
            val failure = runCatching { check(c) }.exceptionOrNull()
            val known = knownDivergences[name]
            if (known != null) {
                if (failure == null) problems += "известное расхождение «$name» ($known) исчезло — уберите из knownDivergences"
            } else if (failure != null) {
                problems += "случай «$name»: ${failure.message}"
            }
        }
        assertTrue("${problems.size} из ${cases.size}:\n" + problems.joinToString("\n"), problems.isEmpty())
    }

    private fun check(c: JsonObject) {
        var now = c.long("now_ms")
        val clock: () -> Long = { now++ }
        val store = DocStore.open(":memory:", clock)
        try {
            for ((i, d) in c.list("docs").withIndex()) {
                val type = d.str("type")
                val id = d.str("id")
                val data = d.obj("data")
                store.put(type, id, 0, data)
                for (v in 1 until i + 1) store.put(type, id, v.toLong(), data)
            }
            now = c.long("now_ms")
            val router = OpRouter(ValueOps(store, clock) { }, TerminalOps(store, clock), MasterOps(store, clock))
            val request = c.obj("request")
            val expect = c.obj("expect")
            val result = runCatching { router.handle(Caller(Role.WORLD, "world-main"), request.str("op"), request) }
            if (expect.bool("ok")) {
                val reply = result.getOrElse { throw AssertionError("ждали успех, а Мост отказал: $it") }
                expect["reply"]?.let { subset("reply", it, JsonObject(reply)) }
            } else {
                val e = result.exceptionOrNull() ?: throw AssertionError("ждали отказ ${expect.str("err")}, а Мост ответил ${result.getOrNull()}")
                val se = e as? StoreException ?: throw AssertionError("ждали StoreException, а выброшено $e")
                assertEquals("код ошибки", expect.str("err"), se.code)
                expect["err_doc"]?.let {
                    val doc = se.current ?: throw AssertionError("в ошибке нет документа, ждали $it")
                    subset("err.doc", it, VJ.docJson(doc))
                }
            }
            for (want in expect["docs_after"]?.objects().orEmpty()) {
                val type = want.str("type")
                val id = want.str("id")
                val doc = store.get(type, id) ?: throw AssertionError("после вызова нет документа $type/$id")
                subset("docs_after $type/$id.data", want.obj("data"), doc.data)
            }
        } finally {
            store.close()
        }
    }

    /** Ожидание ⊆ фактическое: объекты — по ключам ожидания, массивы — длина и поэлементно, числа — как числа, `null` — «поле есть и null». */
    private fun subset(path: String, want: JsonElement, got: JsonElement?) {
        when (want) {
            is JsonObject -> {
                val g = got as? JsonObject ?: throw AssertionError("$path: ждали объект, а $got")
                for ((k, v) in want) {
                    if (k !in g) throw AssertionError("$path.$k: поля нет, ждали $v")
                    subset("$path.$k", v, g.getValue(k))
                }
            }
            is JsonArray -> {
                val g = got as? JsonArray ?: throw AssertionError("$path: ждали массив, а $got")
                if (g.size != want.size) throw AssertionError("$path: длина ${g.size}, ждали ${want.size} ($got)")
                for (i in want.indices) subset("$path[$i]", want[i], g[i])
            }
            is JsonNull -> if (got !is JsonNull) throw AssertionError("$path: ждали null, а $got")
            is JsonPrimitive -> {
                val g = got as? JsonPrimitive ?: throw AssertionError("$path: ждали $want, а $got")
                val same = if (!want.isString && !g.isString && g !is JsonNull) {
                    val a = want.content.toBigDecimalOrNull()
                    val b = g.content.toBigDecimalOrNull()
                    if (a != null && b != null) a.compareTo(b) == 0 else want.content == g.content
                } else {
                    want.isString == g.isString && want.content == g.content
                }
                if (!same) throw AssertionError("$path: ждали $want, а $got")
            }
        }
    }
}
