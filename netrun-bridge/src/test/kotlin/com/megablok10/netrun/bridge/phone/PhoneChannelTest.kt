package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.handover.HandoverRules
import com.megablok10.kit.net.SendOutcome
import com.megablok10.netrun.bridge.Move
import com.megablok10.netrun.bridge.MoveTo
import com.megablok10.netrun.bridge.VJ
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * «Телефон (kit) ↔ Мост»: настоящие сокеты на localhost, телефон — те же LineServer/LineSocketClient/конверт/чек, что у
 * приложения; каждая операция M2 — сдача деки, выдача предмета и эдди, возврат при отказе, защищённый демон при любом исходе,
 * обрыв после отправки (UNKNOWN), рестарт Моста с PENDING.
 */
class PhoneChannelTest {
    @get:Rule val tmp = TemporaryFolder()
    private val closeables = ArrayList<AutoCloseable>()

    private fun <T : AutoCloseable> T.track(): T = also { closeables.add(it) }

    @After fun tearDown() = closeables.reversed().forEach { runCatching { it.close() } }

    private fun rig(path: String = ":memory:") = PhoneRig(path).track()

    // ---------- приём: сдача деки ----------

    @Test fun phoneSubmitsDeckAndGetsReceiptsAndSession() {
        val r = rig()
        val p = r.phone().track()
        val daemon = p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1"))
        val shard = p.itemCard("tr-2", "SHARD", FakePhone.shardPayload("s1"))
        assertEquals(SendOutcome.DELIVERED, p.sendCard(daemon))
        assertEquals(SendOutcome.DELIVERED, p.sendCard(shard))
        // квитанция ушла только после записи: документы уже на месте
        val d = r.itemOf("tr-1")
        assertEquals("inbox:${p.key}", VJ.str(d.data, "owner"))
        assertEquals(daemon.payload, VJ.str(d.data, "payload")) // payload байт в байт
        assertEquals("phone:${p.key}", VJ.str(d.data, "origin"))
        assertEquals("DAEMON", VJ.str(d.data, "kind"))
        // чеки Моста подписаны ключом мира
        r.await("два чека Моста") { p.bodies.mapNotNull { PhoneWire.decodeReceipt(it) }.size == 2 }
        for (c in p.bodies.mapNotNull { PhoneWire.decodeReceipt(it) }) {
            assertEquals(r.worldKey.publicB64, c.receiver)
            assertTrue(Ecdsa.verify(c.receiver, HandoverRules.receiptSignaturePayload(c.id, c.receiver), c.signature))
        }
        assertEquals(SendOutcome.DELIVERED, p.sendEnter(p.enterRequest("e-1", "t03", listOf("tr-1", "tr-2"), "tr-1")))
        r.await("ответ на вход") { p.entered.isNotEmpty() }
        val reply = p.entered.single()
        assertTrue(reply.msg, reply.ok)
        assertTrue(Ecdsa.verify(r.worldKey.publicB64, PhoneWire.enteredSignedBytes(reply.rid, true, reply.session, "", ""), reply.signature))
        assertEquals("pending", VJ.str(r.store.get("session", reply.session)!!.data, "state"))
        assertEquals("deck:${reply.session}", r.owner(d.id))
        assertTrue(VJ.bool(r.item(d.id).data, "protected"))
        assertFalse(VJ.bool(r.itemOf("tr-2").data, "protected"))
    }

    @Test fun repeatedCardMakesNoSecondItemButRepeatsReceipt() {
        val r = rig()
        val p = r.phone().track()
        val card = p.itemCard("tr-1", "SHARD", FakePhone.shardPayload("s1"))
        assertEquals(SendOutcome.DELIVERED, p.sendCard(card))
        assertEquals(SendOutcome.DELIVERED, p.sendCard(card))
        assertEquals(1, r.store.list("item").size)
        r.await("два чека на один id") { p.bodies.mapNotNull { PhoneWire.decodeReceipt(it) }.count { it.id == "tr-1" } == 2 }
    }

    @Test fun badSignatureWrongAddresseeAndGarbagePayloadMakeNoItems() {
        val r = rig()
        val p = r.phone().track()
        val ok = p.itemCard("tr-1", "SHARD", FakePhone.shardPayload("s1"))
        p.sendCard(ok.copy(signature = ok.signature.reversed())) // подпись не сошлась
        p.sendCard(p.itemCard("tr-2", "SHARD", FakePhone.shardPayload("s2"), to = "OTHER")) // адресат не Мост
        p.sendCard(p.itemCard("tr-3", "SHARD", "мусор")) // содержимое не разобралось
        p.sendCard(p.itemCard("tr-4", "WEAPON", FakePhone.shardPayload("s4"))) // неизвестный вид
        r.await("все четыре отвергнуты") { r.log.all.count { "bridge.in_rejected" in it } == 4 }
        assertEquals(emptyList<Any>(), r.store.list("item"))
        assertTrue(p.bodies.none { PhoneWire.decodeReceipt(it) != null })
    }

    @Test fun enterRequestBeforeLastCardWaitsForIt() {
        val r = rig()
        val p = r.phone().track()
        p.sendCard(p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1")))
        p.sendEnter(p.enterRequest("e-1", "t03", listOf("tr-1", "tr-2"), "tr-1"))
        Thread.sleep(300)
        assertTrue(p.entered.isEmpty())
        p.sendCard(p.itemCard("tr-2", "SHARD", FakePhone.shardPayload("s1")))
        r.await("ответ после последней карточки") { p.entered.isNotEmpty() }
        assertTrue(p.entered.single().ok)
    }

    @Test fun forgedEnterRequestIsIgnored() {
        val r = rig()
        val p = r.phone().track()
        p.sendCard(p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1")))
        val req = p.enterRequest("e-1", "t03", listOf("tr-1"), "tr-1")
        p.sendEnter(req.copy(terminal = "t04")) // подпись над другим терминалом
        Thread.sleep(300)
        assertTrue(p.entered.isEmpty())
        assertEquals(0, r.store.list("session").size)
    }

    @Test fun repeatedEnterRequestGetsSameSession() {
        val r = rig()
        val p = r.phone().track()
        p.sendCard(p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1")))
        val req = p.enterRequest("e-1", "t03", listOf("tr-1"), "tr-1")
        p.sendEnter(req)
        r.await("первый ответ") { p.entered.size == 1 }
        p.sendEnter(req) // телефон не получил ответа и повторяет
        r.await("повторный ответ") { p.entered.size == 2 }
        assertEquals(p.entered[0].session, p.entered[1].session)
        assertEquals(1, r.store.list("session").size)
    }

    @Test fun refusedEntryRefundsDeckToPhoneWithReceipts() {
        val r = rig()
        val p = r.phone().track()
        val q = r.phone().track()
        // терминал t03 занят игроком q
        q.sendCard(q.itemCard("q-1", "DAEMON", FakePhone.daemonPayload("dq")))
        q.sendEnter(q.enterRequest("eq", "t03", listOf("q-1"), "q-1"))
        r.await("q вошёл") { q.entered.isNotEmpty() && q.entered.single().ok }
        p.sendCard(p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1")))
        p.sendCard(p.itemCard("tr-2", "SHARD", FakePhone.shardPayload("s1")))
        p.sendEnter(p.enterRequest("e-1", "t03", listOf("tr-1", "tr-2"), "tr-1"))
        r.await("отказ") { p.entered.isNotEmpty() }
        assertEquals("session_state", p.entered.single().code)
        // дека обратно: Мост выдаёт её карточками, телефон отвечает чеками
        r.flush()
        r.await("обе карточки вернулись") { p.itemCards().size == 2 }
        r.await("предметы у телефона") { r.owner(r.itemOf("tr-1").id) == "phone:${p.key}" && r.owner(r.itemOf("tr-2").id) == "phone:${p.key}" }
        for (c in p.itemCards()) {
            assertEquals(r.worldKey.publicB64, c.from)
            assertTrue(Ecdsa.verify(c.from, PhoneWire.itemSignedBytes(c), c.signature))
        }
    }

    @Test fun staleInboxCardsGoBackToPhone() {
        val r = rig()
        val p = r.phone().track()
        p.sendCard(p.itemCard("tr-1", "SHARD", FakePhone.shardPayload("s1")))
        assertEquals(0, r.inbox.sweep())
        r.store.get("settings", "global")!!.let { r.store.put("settings", "global", it.ver, VJ.with(it.data, "inbox_timeout_s" to JsonPrimitive(0L))) }
        Thread.sleep(5)
        assertEquals(1, r.inbox.sweep())
        r.flush()
        r.await("карточка вернулась") { p.itemCards().size == 1 }
        r.await("предмет у телефона") { r.owner(r.itemOf("tr-1").id) == "phone:${p.key}" }
        assertEquals(0, r.inbox.sweep())
    }

    // ---------- выдача: предметы и эдди ----------

    @Test fun masterIssuesItemAndEddiesPhoneConfirmsWithReceipts() {
        val r = rig()
        val p = r.phone().track()
        r.store.put("item", "it_n1", 0, VJ.obj("owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload("n1")), "protected" to VJ.p(false), "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?)))
        val res = r.ops.issueToPhone(r.master, "give:1", p.key, listOf("it_n1"), 40, "награда")
        assertTrue(res.body.toString(), res.ok)
        assertEquals("PENDING", VJ.str(r.item("it_n1").data, "handover"))
        r.flush()
        r.await("карточки дошли") { p.itemCards().size == 1 && p.moneyCards().size == 1 }
        r.await("оба чека") { r.owner("it_n1") == "phone:${p.key}" && VJ.str(r.store.list("payout").single().data, "state") == "CONFIRMED" }
        assertEquals(40L, p.moneyCards().single().amount)
        val money = p.moneyCards().single()
        assertTrue(Ecdsa.verify(money.from, PhoneWire.moneySignedBytes(money.id, money.from, money.to, money.amount, money.memo), money.signature))
        assertEquals(null, VJ.str(r.item("it_n1").data, "handover"))
        assertEquals(0, r.flush()) // ничего не осталось
    }

    @Test fun foreignOrForgedReceiptDoesNotConfirm() {
        val r = rig()
        val p = r.phone().track()
        val other = r.phone().track()
        p.autoReceipt = false
        r.store.put("item", "it_n1", 0, VJ.obj("owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload("n1")), "protected" to VJ.p(false), "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?)))
        r.ops.issueToPhone(r.master, "give:1", p.key, listOf("it_n1"), 0, "x")
        r.flush()
        r.await("карточка дошла") { p.itemCards().size == 1 }
        val tid = p.itemCards().single().id
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover"))
        other.sendReceipt(tid) // чек от чужого ключа
        Thread.sleep(300)
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover"))
        p.sendDm(PhoneWire.encodeReceipt(ReceiptCard(tid, p.key, "AAAA"))) // подпись не сошлась
        Thread.sleep(300)
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover"))
        p.sendReceipt(tid)
        r.await("настоящий чек") { r.owner("it_n1") == "phone:${p.key}" }
    }

    // ---------- защищённый демон при любом исходе ----------

    @Test fun protectedDaemonComesBackToPhoneOnEveryOutcome() {
        for (outcome in listOf("clean", "emergency", "soft_ice", "black_ice")) {
            val r = rig()
            val p = r.phone().track()
            p.sendCard(p.itemCard("tr-1", "DAEMON", FakePhone.daemonPayload("d1")))
            p.sendCard(p.itemCard("tr-2", "SHARD", FakePhone.shardPayload("s1")))
            p.sendEnter(p.enterRequest("e-$outcome", "t03", listOf("tr-1", "tr-2"), "tr-1"))
            r.await("вход $outcome") { p.entered.isNotEmpty() }
            val sid = p.entered.single().session
            r.store.get("session", sid)!!.let { r.store.put("session", sid, it.ver, VJ.with(it.data, "state" to JsonPrimitive("active"))) }
            val shardMove = if (outcome == "clean" || outcome == "soft_ice" || outcome == "emergency") MoveTo.PHONE else MoveTo.NODE
            val res = r.ops.finishRun(r.world, "finish:$sid", sid, outcome, "node_07", false, listOf(Move(r.itemOf("tr-2").id, shardMove)))
            assertTrue("$outcome: ${res.body}", res.ok)
            r.flush()
            val protectedId = r.itemOf("tr-1").id
            r.await("$outcome: защищённый демон у телефона") { r.owner(protectedId) == "phone:${p.key}" }
            assertTrue(p.itemCards().any { it.payload == FakePhone.daemonPayload("d1") })
        }
    }

    // ---------- обрыв после отправки и рестарт ----------

    /** Телефон-«чёрная дыра»: принимает соединение, читает строку и обрывает без квитанции — отправитель видит UNKNOWN. */
    private class BlackHole : AutoCloseable {
        val server = ServerSocket(0)
        val lines = CopyOnWriteArrayList<String>()
        @Volatile private var open = true
        init {
            Thread {
            while (open) {
                try {
                    server.accept().use { s -> s.getInputStream().bufferedReader().readLine()?.let { lines.add(it) } }
                } catch (e: java.io.IOException) {
                    break
                }
            }
            }.also { it.isDaemon = true; it.start() }
        }

        override fun close() { open = false; server.close() }
    }

    @Test fun unknownAfterSendKeepsDeliveredAndNeverRollsBack() {
        val hole = BlackHole().track()
        val r = rig()
        val key = Ecdsa.encodeKey(Ecdsa.generateKeyPair().public)
        r.network.addStatic(key, "127.0.0.1", hole.server.localPort)
        r.store.put("item", "it_n1", 0, VJ.obj("owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload("n1")), "protected" to VJ.p(false), "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?)))
        r.ops.issueToPhone(r.master, "give:1", key, listOf("it_n1"), 0, "x")
        r.flush()
        assertEquals(1, hole.lines.size)
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover")) // не PENDING: карточка могла дойти
        assertEquals("outbox:$key", r.owner("it_n1"))
        assertTrue(r.log.has("outcome=UNKNOWN"))
        assertTrue(r.log.has("status=DELIVERED"))
        // сама по себе новая отправка до срока не идёт
        r.flush()
        assertEquals(1, hole.lines.size)
    }

    @Test fun unknownIsNotRetriedAtAnotherAddressAndNotReachedIsRolledBack() {
        val calls = CopyOnWriteArrayList<String>()
        var outcome = SendOutcome.UNKNOWN
        val sender = object : PhoneSender {
            override fun isOnline(pubKeyB64: String) = true
            override fun send(pubKeyB64: String, line: String): SendOutcome { calls.add(line); return outcome }
        }
        val r = PhoneRig(deliveryResendMs = 0L) { sender }.track()
        r.store.put("item", "it_n1", 0, VJ.obj("owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload("n1")), "protected" to VJ.p(false), "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?)))
        r.ops.issueToPhone(r.master, "give:1", "KEY_P", listOf("it_n1"), 0, "x")
        r.flush()
        assertEquals(1, calls.size) // одна отправка на карточку: перебор адресов — внутри PeerDirectory и только после NOT_REACHED
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover"))
        outcome = SendOutcome.NOT_REACHED
        r.flush() // DELIVERED без чека — досылается той же карточкой; NOT_REACHED при досылке статус не трогает
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover"))
        val first = PhoneWire.decodeItem(PhoneWire.decodeChat(calls[0])!!.body)!!
        val again = PhoneWire.decodeItem(PhoneWire.decodeChat(calls[1])!!.body)!!
        assertEquals(first.id, again.id)
        assertEquals(first.payload, again.payload)
    }

    @Test fun notReachedOnFirstSendRollsBackToPendingAndOfflineStaysPending() {
        var online = false
        var outcome = SendOutcome.NOT_REACHED
        val calls = AtomicInteger()
        val sender = object : PhoneSender {
            override fun isOnline(pubKeyB64: String) = online
            override fun send(pubKeyB64: String, line: String): SendOutcome { calls.incrementAndGet(); return outcome }
        }
        val r = PhoneRig { sender }.track()
        r.store.put("item", "it_n1", 0, VJ.obj("owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload("n1")), "protected" to VJ.p(false), "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?)))
        r.ops.issueToPhone(r.master, "give:1", "KEY_P", listOf("it_n1"), 0, "x")
        r.flush()
        assertEquals(0, calls.get()) // не видно — не отправляем, остаётся PENDING
        assertEquals("PENDING", VJ.str(r.item("it_n1").data, "handover"))
        online = true
        r.flush()
        assertEquals(1, calls.get())
        assertEquals("PENDING", VJ.str(r.item("it_n1").data, "handover")) // точно не ушла — откат
        outcome = SendOutcome.DELIVERED
        r.flush()
        assertEquals("DELIVERED", VJ.str(r.item("it_n1").data, "handover"))
    }

    @Test fun restartedBridgeDeliversPendingFromDocumentsWithSameWorldKey() {
        val db = tmp.root.resolve("bridge.db").path
        val keyFile = tmp.root.resolve("bridge.db.worldkey")
        val key1 = WorldKey.loadOrCreate(keyFile)
        val phone = FakePhone(kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO), key1.publicB64).track()
        val first = PhoneRig(db, key = key1)
        first.store.put("item", "it_n1", 0, VJ.obj("owner" to VJ.p("node:node_07"), "kind" to VJ.p("SHARD"), "payload" to VJ.p(FakePhone.shardPayload("n1")), "protected" to VJ.p(false), "origin" to VJ.p("node:node_07"), "in_transfer" to VJ.p(null as String?), "out_transfer" to VJ.p(null as String?), "handover" to VJ.p(null as String?)))
        first.ops.issueToPhone(first.master, "give:1", phone.key, listOf("it_n1"), 25, "x")
        first.flush() // телефона не видно — всё осталось PENDING
        first.close()
        // «новый процесс»: тот же ключ из файла, те же документы
        val second = PhoneRig(db, key = WorldKey.loadOrCreate(keyFile)).track()
        assertEquals(key1.publicB64, second.worldKey.publicB64)
        phone.connect(second.network.port)
        second.network.addStatic(phone.key, "127.0.0.1", phone.port)
        assertEquals("PENDING", VJ.str(second.item("it_n1").data, "handover"))
        assertEquals("PENDING", VJ.str(second.store.list("payout").single().data, "state"))
        assertEquals(2, second.flush()) // и предмет, и эдди — из документов, без повторного вызова операции
        second.await("карточки дошли") { phone.itemCards().size == 1 && phone.moneyCards().size == 1 }
        second.await("оба чека") { second.owner("it_n1") == "phone:${phone.key}" && VJ.str(second.store.list("payout").single().data, "state") == "CONFIRMED" }
        val card = phone.itemCards().single()
        assertTrue(Ecdsa.verify(key1.publicB64, PhoneWire.itemSignedBytes(card), card.signature))
    }
}
