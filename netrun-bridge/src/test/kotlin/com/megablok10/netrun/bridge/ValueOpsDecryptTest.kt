package com.megablok10.netrun.bridge

import com.megablok10.rules.Daemon
import com.megablok10.rules.DaemonEffect
import com.megablok10.rules.ItemPayloadCodec
import com.megablok10.rules.ShardPayload
import com.megablok10.rules.Tier
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `op.decrypt_item` (протокол, 6.8): расшифровка шарда в деке. Меняется ровно один флаг «расшифрован» в `payload`; владелец, версия
 * цепочки передач и количество предметов остаются, аудитор чист. Тир DECRYPT проверяет `DecryptRules.bestDecrypter`.
 */
class ValueOpsDecryptTest {
    private val f = BreachFixture()
    private val sid: String

    init {
        // DECRYPT тира HARD (2) в деке A как рабочий демон — сдаётся при входе вместе с остальными.
        putItem("it_dec", "inbox:${f.keyA}", "phone:${f.keyA}", "DAEMON", daemonPayload("it_dec", Tier.HARD))
        sid = f.enter(f.keyA, "t03", "it_dec", "it_ex")
    }

    private fun daemonPayload(id: String, tier: Tier, effect: DaemonEffect = DaemonEffect.DECRYPT) =
        ItemPayloadCodec.encodeDaemon(Daemon(id, id, listOf("1C", "55"), tier, effect))

    private fun shardPayload(id: String, tier: Int, decrypted: Boolean = false, action: Boolean = true) =
        ItemPayloadCodec.encodeShard(ShardPayload(id, action, tier, "оценка", "Схемы $id", "мета", "Тело $id", 0, decrypted))

    private fun putItem(id: String, owner: String, origin: String, kind: String, payload: String) {
        val base = JsonObject(
            mapOf(
                "owner" to JsonPrimitive(owner), "kind" to JsonPrimitive(kind), "payload" to JsonPrimitive(payload),
                "protected" to JsonPrimitive(false), "origin" to JsonPrimitive(origin),
                "in_transfer" to kotlinx.serialization.json.JsonNull, "out_transfer" to kotlinx.serialization.json.JsonNull,
                "handover" to kotlinx.serialization.json.JsonNull,
            ) + ItemDecode.fields(kind, payload),
        )
        f.store.put("item", id, 0, base)
    }

    /** Шард в деке сессии [session] (добавлен и в документ `deck`, как после `op.take_from_node`). */
    private fun shardInDeck(id: String, tier: Int, session: String = sid, payload: String = shardPayload(id, tier)) {
        putItem(id, "deck:$session", "node:node_07", "SHARD", payload)
        val d = f.store.get("deck", session)!!
        f.store.put("deck", session, d.ver, VJ.with(d.data, "items" to JsonArray(VJ.list(d.data, "items").plus(id).map { JsonPrimitive(it) })))
    }

    private fun ver(id: String) = f.store.get("item", id)!!.ver
    private fun rid(id: String, v: Long = ver(id)) = "decrypt:$sid:$id:$v"
    private fun decrypt(id: String, rid: String = rid(id), ver: Long = ver(id), session: String = sid) =
        f.ops.decryptItem(f.world, rid, session, id, ver)

    private fun conserved(before: Int) {
        assertEquals(before, f.store.list("item").size)
        assertEquals(emptyList<Violation>(), Auditor(f.store).check())
    }

    @Test fun successChangesOnlyTheDecryptedFlag() {
        shardInDeck("sh_e", 2)
        val before = f.store.get("item", "sh_e")!!
        val total = f.store.list("item").size
        val r = decrypt("sh_e")
        assertTrue(r.body.toString(), r.ok)
        assertFalse(r.replayed)
        assertTrue(VJ.bool(r.body, "changed"))
        assertEquals("Схемы sh_e", VJ.str(r.body, "title"))
        assertEquals("Тело sh_e", VJ.str(r.body, "body"))
        val after = f.store.get("item", "sh_e")!!
        assertEquals(before.ver + 1, after.ver)
        val was = VJ.str(before.data, "payload")!!.split("|")
        val now = VJ.str(after.data, "payload")!!.split("|")
        assertEquals(was.size, now.size)
        assertEquals("1", now[9])
        assertEquals(was.filterIndexed { i, _ -> i != 9 }, now.filterIndexed { i, _ -> i != 9 }) // остальное — байт в байт
        val shard = ItemPayloadCodec.decodeShard(VJ.str(after.data, "payload")!!)!!
        assertTrue(shard.decrypted)
        assertEquals(ItemPayloadCodec.decodeShard(VJ.str(before.data, "payload")!!)!!.copy(decrypted = true), shard)
        val field = after.data["shard"] as JsonObject
        assertTrue(VJ.bool(field, "decrypted"))
        assertFalse(VJ.bool(field, "encrypted"))
        for (k in listOf("owner", "origin", "protected", "in_transfer", "out_transfer", "handover", "kind")) {
            assertEquals(k, before.data[k], after.data[k])
        }
        conserved(total)
    }

    @Test fun replayReturnsSavedAnswerAndWritesNothingTwice() {
        shardInDeck("sh_e", 1)
        val first = decrypt("sh_e")
        val v = ver("sh_e")
        val again = f.ops.decryptItem(f.world, "decrypt:$sid:sh_e:${v - 1}", sid, "sh_e", v - 1)
        assertTrue(again.replayed)
        assertEquals(first.body, again.body)
        assertEquals(v, ver("sh_e"))
    }

    @Test fun sameRidWithOtherParamsIsRidMismatch() {
        shardInDeck("sh_e", 1)
        shardInDeck("sh_f", 1)
        val rid = "decrypt:$sid:x:1"
        assertTrue(decrypt("sh_e", rid = rid).ok)
        try {
            decrypt("sh_f", rid = rid)
            org.junit.Assert.fail("ждали rid_mismatch")
        } catch (e: StoreException) {
            assertEquals("rid_mismatch", e.code)
        }
    }

    @Test fun lateCallWithNewRidSeesChangedFalse() {
        shardInDeck("sh_e", 1)
        assertTrue(decrypt("sh_e").ok)
        val payload = VJ.str(f.store.get("item", "sh_e")!!.data, "payload")
        val late = decrypt("sh_e") // новая версия → новый rid, шард уже открыт
        assertTrue(late.body.toString(), late.ok)
        assertFalse(VJ.bool(late.body, "changed"))
        assertEquals(payload, VJ.str(f.store.get("item", "sh_e")!!.data, "payload"))
    }

    @Test fun alreadyOpenShardIsUnchangedAndNotBumped() {
        shardInDeck("sh_o", 1, payload = shardPayload("sh_o", 1, decrypted = true))
        shardInDeck("sh_n", 1, payload = shardPayload("sh_n", 1, action = false))
        for (id in listOf("sh_o", "sh_n")) {
            val v = ver(id)
            val r = decrypt(id)
            assertTrue(r.body.toString(), r.ok)
            assertFalse(VJ.bool(r.body, "changed"))
            assertEquals(v, ver(id))
        }
    }

    @Test fun futureFieldsAfterTheTenthSurvive() {
        val payload = shardPayload("sh_f", 1) + "|будущее|поле"
        shardInDeck("sh_f", 1, payload = payload)
        assertTrue(decrypt("sh_f").ok)
        val now = VJ.str(f.store.get("item", "sh_f")!!.data, "payload")!!
        assertTrue(now.endsWith("|1|будущее|поле"))
        assertEquals(payload.split("|").size, now.split("|").size)
    }

    @Test fun itemInOutboxIsWrongOwner() {
        shardInDeck("sh_e", 1)
        val d = f.store.get("item", "sh_e")!!
        f.store.put("item", "sh_e", d.ver, VJ.with(d.data, "owner" to JsonPrimitive("outbox:KEY_X"), "handover" to JsonPrimitive("PENDING")))
        val payload = VJ.str(f.store.get("item", "sh_e")!!.data, "payload")
        val r = decrypt("sh_e")
        assertFalse(r.ok)
        assertEquals("wrong_owner", r.code)
        assertEquals(payload, VJ.str(f.store.get("item", "sh_e")!!.data, "payload"))
    }

    @Test fun otherPlayersDeckIsWrongOwner() {
        val b = f.enterB()
        shardInDeck("sh_b", 1, session = b)
        val r = decrypt("sh_b")
        assertFalse(r.ok)
        assertEquals("wrong_owner", r.code)
    }

    @Test fun notAShardIsBadRequest() {
        val code = try { decrypt("it_ex"); null } catch (e: StoreException) { e.code }
        assertEquals("bad_request", code)
        putItem("sh_bad", "deck:$sid", "node:node_07", "SHARD", "не разбирается")
        val code2 = try { decrypt("sh_bad"); null } catch (e: StoreException) { e.code }
        assertEquals("bad_request", code2)
    }

    @Test fun unknownSessionOrItemIsNotFound() {
        val a = try { decrypt("nope", rid = "decrypt:x", ver = 1); null } catch (e: StoreException) { e.code }
        assertEquals("not_found", a)
        shardInDeck("sh_e", 1)
        val b = try { decrypt("sh_e", rid = "decrypt:y", session = "s_nope"); null } catch (e: StoreException) { e.code }
        assertEquals("not_found", b)
    }

    @Test fun staleVersionIsConflictAndKept() {
        shardInDeck("sh_e", 1)
        val r = decrypt("sh_e", ver = ver("sh_e") + 5)
        assertFalse(r.ok)
        assertEquals("version_conflict", r.code)
        val repeat = decrypt("sh_e", rid = rid("sh_e"), ver = ver("sh_e") + 5)
        assertTrue(repeat.replayed)
    }

    @Test fun decrypterTierMustCoverTheShard() {
        shardInDeck("sh_3", 3)
        val r = decrypt("sh_3") // DECRYPT HARD (2) не берёт тир 3
        assertFalse(r.ok)
        assertEquals("no_decrypter", r.code)
        shardInDeck("sh_2", 2)
        assertTrue(decrypt("sh_2").ok) // тир 2 — берёт
    }

    @Test fun decrypterInCargoDoesNotCount() {
        val b = f.enterB() // у B нет DECRYPT в рабочих
        shardInDeck("sh_b", 1, session = b)
        putItem("it_loot_dec", "deck:$b", "node:node_07", "DAEMON", daemonPayload("it_loot_dec", Tier.NIGHTMARE))
        val d = f.store.get("deck", b)!!
        f.store.put("deck", b, d.ver, VJ.with(d.data, "items" to JsonArray(VJ.list(d.data, "items").plus("it_loot_dec").map { JsonPrimitive(it) })))
        val r = f.ops.decryptItem(f.world, "decrypt:$b:sh_b:${ver("sh_b")}", b, "sh_b", ver("sh_b"))
        assertFalse(r.ok)
        assertEquals("no_decrypter", r.code)
    }

    @Test fun inactiveSessionIsRefused() {
        shardInDeck("sh_e", 1)
        val s = f.store.get("session", sid)!!
        f.store.put("session", sid, s.ver, VJ.with(s.data, "state" to JsonPrimitive("closed")))
        val r = decrypt("sh_e")
        assertFalse(r.ok)
        assertEquals("session_state", r.code)
    }

    @Test fun decryptedShardKeepsTravellingAndPhoneReadsIt() {
        shardInDeck("sh_e", 2)
        assertTrue(decrypt("sh_e").ok)
        val payload = VJ.str(f.store.get("item", "sh_e")!!.data, "payload")!!
        assertNotEquals(shardPayload("sh_e", 2), payload)
        assertTrue(ItemPayloadCodec.decodeShard(payload)!!.decrypted) // телефон берёт флаг из карточки
        assertEquals(Tier.HARD.level, ItemDecode.fields("SHARD", payload)["shard"]?.let { VJ.lng(it, "tier").toInt() })
    }

    @Test fun bridgeRoleMayNotDecrypt() {
        shardInDeck("sh_e", 1)
        val code = try { f.ops.decryptItem(Caller(Role.BRIDGE, "b"), "decrypt:x", sid, "sh_e", ver("sh_e")); null } catch (e: StoreException) { e.code }
        assertEquals("forbidden", code)
    }
}
