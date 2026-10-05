package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.netrun.bridge.GiveTarget
import com.megablok10.netrun.bridge.Move
import com.megablok10.netrun.bridge.MoveTo
import com.megablok10.netrun.bridge.VJ
import com.megablok10.netrun.bridge.giveItem
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `op.give_item` на телефон (протокол, 6.7): настоящие сокеты, карточка Handover от ключа мира, чек получателя. Отправитель — тоже
 * телефон, прошедший вход; его телефон в передаче не участвует.
 */
class GivePhoneTest {
    private val closeables = ArrayList<AutoCloseable>()

    private fun <T : AutoCloseable> T.track(): T = also { closeables.add(it) }

    @After fun tearDown() = closeables.reversed().forEach { runCatching { it.close() } }

    private fun shard(r: PhoneRig, id: String) {
        r.store.put(
            "item", id, 0,
            VJ.obj(
                "owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload(id)), "protected" to VJ.p(false),
                "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?),
            ),
        )
    }

    /** Игрок [p] вошёл с демоном и шардом, курок нажат; в грузе — шард `it_n1`, взятый в узле. Возвращает сессию. */
    private fun runWithLoot(r: PhoneRig, p: FakePhone): String {
        p.sendCard(p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1")))
        p.sendCard(p.itemCard("tr-2", "SHARD", FakePhone.shardPayload("s1")))
        p.sendEnter(p.enterRequest("e-give", "t03", listOf("tr-1", "tr-2"), "tr-1"))
        r.await("вход") { p.entered.isNotEmpty() }
        val sid = p.entered.single().session
        r.store.get("session", sid)!!.let { r.store.put("session", sid, it.ver, VJ.with(it.data, "state" to JsonPrimitive("active"))) }
        shard(r, "it_n1")
        assertTrue(r.ops.takeFromNode(r.world, "take:$sid:it_n1", sid, "node_07", "it_n1").ok)
        return sid
    }

    @Test fun cardGoesToTheContactFromTheWorldKeyAndReceiptCompletesTheGive() {
        val r = PhoneRig().track()
        val sender = r.phone().track()
        val contact = r.phone().track()
        val sid = runWithLoot(r, sender)
        val ver = r.item("it_n1").ver
        val res = r.ops.giveItem(r.world, "give:$sid:it_n1:$ver", sid, "it_n1", ver, GiveTarget.Phone(contact.key))
        assertTrue(res.body.toString(), res.ok)
        assertEquals("outbox:${contact.key}", r.owner("it_n1"))
        assertEquals("PENDING", VJ.str(r.item("it_n1").data, "handover"))
        r.flush()
        r.await("карточка у контакта") { contact.itemCards().size == 1 }
        val card = contact.itemCards().single()
        assertEquals(r.worldKey.publicB64, card.from) // от ключа мира, а не от отправителя: подписи «от» нет (решение владельца)
        assertEquals(contact.key, card.to)
        assertEquals(VJ.str(res.body, "transfer"), card.id)
        assertEquals(FakePhone.shardPayload("it_n1"), card.payload) // payload байт в байт
        assertTrue(Ecdsa.verify(card.from, PhoneWire.itemSignedBytes(card), card.signature))
        r.await("чек контакта") { r.owner("it_n1") == "phone:${contact.key}" }
        assertEquals(null, VJ.str(r.item("it_n1").data, "handover"))
        assertEquals(0, sender.itemCards().count { it.payload == FakePhone.shardPayload("it_n1") }) // телефон отправителя не участвует
        assertEquals(0, r.flush()) // доставлено и подтверждено — досылать нечего
        // забег отправителя закрывается без отданного: он вне риска забега
        val fin = r.ops.finishRun(r.world, "finish:$sid", sid, "black_ice", "node_07", false, listOf(Move(r.itemOf("tr-2").id, MoveTo.NODE)))
        assertTrue(fin.body.toString(), fin.ok)
        assertEquals("phone:${contact.key}", r.owner("it_n1"))
    }

    @Test fun contactWhoIsOfflineKeepsTheCardPendingAndTheRunIsNotWaiting() {
        val r = PhoneRig().track()
        val sender = r.phone().track()
        val sid = runWithLoot(r, sender)
        val absent = Ecdsa.encodeKey(Ecdsa.generateKeyPair().public) // адреса нет: телефон не в сети
        val ver = r.item("it_n1").ver
        assertTrue(r.ops.giveItem(r.world, "give:$sid:it_n1:$ver", sid, "it_n1", ver, GiveTarget.Phone(absent)).ok)
        assertEquals(0, r.flush())
        assertEquals("outbox:$absent", r.owner("it_n1"))
        assertEquals("PENDING", VJ.str(r.item("it_n1").data, "handover"))
        val fin = r.ops.finishRun(r.world, "finish:$sid", sid, "clean", "node_07", false, listOf(Move(r.itemOf("tr-2").id, MoveTo.PHONE)))
        assertTrue(fin.body.toString(), fin.ok)
        assertEquals("outbox:$absent", r.owner("it_n1")) // карточка ждёт в Outbox
    }

    @Test fun repeatedGiveDoesNotSendASecondCard() {
        val r = PhoneRig().track()
        val sender = r.phone().track()
        val contact = r.phone().track()
        val sid = runWithLoot(r, sender)
        val ver = r.item("it_n1").ver
        val rid = "give:$sid:it_n1:$ver"
        r.ops.giveItem(r.world, rid, sid, "it_n1", ver, GiveTarget.Phone(contact.key))
        r.flush()
        r.await("чек") { r.owner("it_n1") == "phone:${contact.key}" }
        val again = r.ops.giveItem(r.world, rid, sid, "it_n1", ver, GiveTarget.Phone(contact.key))
        assertTrue(again.replayed)
        assertEquals(0, r.flush())
        assertEquals(1, contact.itemCards().size)
    }
}
