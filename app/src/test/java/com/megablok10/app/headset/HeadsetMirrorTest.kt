package com.megablok10.app.headset

import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.TestPlayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Телефон как источник данных для очков: что и когда уходит в кадрах и как исполняются команды очков (на фейках, без сети и Room). */
@OptIn(ExperimentalCoroutinesApi::class)
class HeadsetMirrorTest {
    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val carol = TestPlayer("Carol")

    private class FakeChat(val me: Identity) : HeadsetChatPort {
        val stamp = MutableStateFlow(0)
        val messages = mutableListOf<ChatMessageEntity>()
        val names = mutableMapOf<String, String>()
        val sentDirect = mutableListOf<Pair<String, String>>()
        val sentFaction = mutableListOf<String>()
        private var nextId = 1L

        fun add(from: String, to: String, body: String, ts: Long, type: String = "DM", status: Int = MessageStatus.NONE, callsign: String = "") {
            messages += ChatMessageEntity(nextId++, type, from, callsign, me.faction, to, body, ts, status)
            stamp.value++
        }

        fun setStatus(id: Long, status: Int) {
            val i = messages.indexOfFirst { it.id == id }
            messages[i] = messages[i].copy(status = status)
            stamp.value++
        }

        override fun changes(me: Identity): Flow<Unit> = stamp.map { }
        override suspend fun directPeers(me: String) = messages.filter { it.type == "DM" }.map { if (it.fromPubKeyB64 == me) it.toPubKeyB64 else it.fromPubKeyB64 }.distinct()
        override suspend fun recentDirect(me: String, peerPubKey: String, limit: Int) = messages.filter {
            it.type == "DM" && ((it.fromPubKeyB64 == me && it.toPubKeyB64 == peerPubKey) || (it.fromPubKeyB64 == peerPubKey && it.toPubKeyB64 == me))
        }.sortedBy { it.timestamp }.takeLast(limit)
        override suspend fun recentFaction(faction: String, limit: Int) = messages.filter { it.type == "FACTION" && it.faction == faction }.sortedBy { it.timestamp }.takeLast(limit)
        override suspend fun peerCallsign(pubKey: String) = names[pubKey]
        override suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, text: String): Boolean { sentDirect += peerPubKeyB64 to text; return true }
        override suspend fun sendFaction(identity: Identity, text: String) { sentFaction += text }
    }

    private class MemRead : HeadsetReadState {
        val map = mutableMapOf<String, Long>()
        override fun lastRead(thread: String) = map[thread]
        override fun setLastRead(thread: String, upToMs: Long) { map[thread] = upToMs }
    }

    private class Session(val chat: FakeChat, val read: MemRead) {
        val frames = mutableListOf<HeadsetOut>()
        val commands = Channel<HeadsetCommand>(Channel.UNLIMITED)
        val ready = mutableListOf<Boolean>()
        fun take(): List<HeadsetOut> = frames.toList().also { frames.clear() }
    }

    private fun TestScope.start(chat: FakeChat, read: MemRead = MemRead()): Session {
        val s = Session(chat, read)
        val mirror = HeadsetMirror(chat, { chat.me }, read, onReady = { s.ready += it })
        launch { mirror.serve({ f -> s.frames += f; true }, s.commands) }
        runCurrent()
        return s
    }

    private suspend fun Session.send(cmd: HeadsetCommand, scope: TestScope) { commands.send(cmd); scope.runCurrent() }

    private fun chatWithHistory(): FakeChat = FakeChat(alice.identity).apply {
        names[bob.key] = "Bob"
        add(bob.key, "", "всем привет", 1_000, "FACTION", callsign = "Bob")
        add(bob.key, alice.key, "как дела", 2_000, callsign = "Bob")
        add(alice.key, bob.key, "норм", 3_000, status = MessageStatus.DELIVERED)
    }

    @Test fun helloGoesFirstAndCommandsBeforeAckAreIgnored() = runTest {
        val s = start(chatWithHistory())
        assertEquals(listOf<HeadsetOut>(HeadsetOut.Hello("Alice")), s.take())
        s.send(HeadsetCommand.Resync, this)
        s.send(HeadsetCommand.SendText("faction", "yes"), this)
        assertTrue("до hello_ack очки не слушают", s.take().isEmpty())
        assertTrue(s.chat.sentFaction.isEmpty())
        assertTrue(s.ready.isEmpty())
        s.commands.close()
    }

    @Test fun afterAckSnapshotHasFactionAndDirectThreadsWithMessages() = runTest {
        val s = start(chatWithHistory())
        s.take()
        s.send(HeadsetCommand.HelloAck(1), this)
        val frames = s.take()
        val threads = frames.filterIsInstance<HeadsetOut.Threads>().single().items
        assertEquals(listOf("faction", bob.key), threads.map { it.id })
        assertEquals(listOf("FACTION", "DM"), threads.map { it.kind })
        assertEquals(listOf("Малстром", "Bob"), threads.map { it.title })
        assertEquals("норм", threads[1].lastText)
        assertEquals(3L, threads[1].lastTs)
        val dm = frames.filterIsInstance<HeadsetOut.Messages>().single { it.thread == bob.key }.items
        assertEquals(listOf("как дела", "норм"), dm.map { it.text })
        assertEquals(listOf(false, true), dm.map { it.mine })
        assertEquals(listOf("delivered", "delivered"), dm.map { it.status })
        assertEquals(listOf("", ""), dm.map { it.from })
        val fac = frames.filterIsInstance<HeadsetOut.Messages>().single { it.thread == "faction" }.items
        assertEquals("Bob", fac.single().from)
        assertEquals(listOf(true), s.ready)
        s.commands.close()
        runCurrent()
        assertEquals(listOf(true, false), s.ready)
    }

    @Test fun historyThatWasThereBeforeTheFirstConnectionCountsAsRead() = runTest {
        val s = start(chatWithHistory())
        s.send(HeadsetCommand.HelloAck(1), this)
        val threads = s.take().filterIsInstance<HeadsetOut.Threads>().single().items
        assertEquals(listOf(0, 0), threads.map { it.unread })
        s.commands.close()
    }

    @Test fun serviceCardsAreHiddenAndThreadWithOnlyCardsIsNotListed() = runTest {
        val chat = chatWithHistory()
        chat.add(carol.key, alice.key, Mb10QrCodec.encodeContact(carol.key, "Carol", "Малстром"), 4_000, callsign = "Carol")
        chat.add(bob.key, alice.key, Mb10QrCodec.encodeContact(bob.key, "Bob", "Малстром"), 5_000, callsign = "Bob")
        val s = start(chat)
        s.send(HeadsetCommand.HelloAck(1), this)
        val frames = s.take()
        val threads = frames.filterIsInstance<HeadsetOut.Threads>().single().items
        assertEquals("тред только с карточкой не показываем", listOf("faction", bob.key), threads.map { it.id })
        assertEquals("последним в треде остаётся текст, не карточка", "норм", threads[1].lastText)
        val dm = frames.filterIsInstance<HeadsetOut.Messages>().single { it.thread == bob.key }.items
        assertEquals(listOf("как дела", "норм"), dm.map { it.text })
        s.commands.close()
    }

    @Test fun newIncomingMessageGivesMessageFrameAndUnreadCount() = runTest {
        val chat = chatWithHistory()
        val s = start(chat)
        s.send(HeadsetCommand.HelloAck(1), this)
        s.take()
        chat.add(bob.key, alice.key, "ты тут?", 9_000, callsign = "Bob")
        runCurrent()
        val frames = s.take()
        val msg = frames.filterIsInstance<HeadsetOut.Message>().single().msg
        assertEquals("ты тут?", msg.text)
        assertFalse(msg.mine)
        assertEquals(bob.key, msg.thread)
        assertEquals(9L, msg.ts)
        val thread = frames.filterIsInstance<HeadsetOut.Threads>().single().items.single { it.id == bob.key }
        assertEquals(1, thread.unread)
        s.commands.close()
    }

    @Test fun markReadClearsUnreadForThatThreadOnly() = runTest {
        val chat = chatWithHistory()
        val s = start(chat)
        s.send(HeadsetCommand.HelloAck(1), this)
        chat.add(bob.key, alice.key, "раз", 9_000, callsign = "Bob")
        chat.add(bob.key, alice.key, "два", 9_500, "FACTION", callsign = "Bob")
        runCurrent()
        s.take()
        s.send(HeadsetCommand.MarkRead(bob.key), this)
        val threads = s.take().filterIsInstance<HeadsetOut.Threads>().single().items
        assertEquals(0, threads.single { it.id == bob.key }.unread)
        assertEquals("во фракции осталось непрочитанное", 1, threads.single { it.id == "faction" }.unread)
        assertEquals(9_000L, s.read.map[bob.key])
        s.commands.close()
    }

    @Test fun statusChangeOfMyMessageIsSentOnceAndMappedToDelivered() = runTest {
        val chat = FakeChat(alice.identity).apply { add(alice.key, bob.key, "привет", 1_000, status = MessageStatus.PENDING) }
        chat.names[bob.key] = "Bob"
        val s = start(chat)
        s.send(HeadsetCommand.HelloAck(1), this)
        assertEquals("sent", s.take().filterIsInstance<HeadsetOut.Messages>().single { it.thread == bob.key }.items.single().status)
        chat.setStatus(1, MessageStatus.READ)
        runCurrent()
        assertEquals("delivered", s.take().filterIsInstance<HeadsetOut.Message>().single().msg.status)
        chat.stamp.value++ // ничего не изменилось: повтора нет
        runCurrent()
        assertTrue(s.take().filterIsInstance<HeadsetOut.Message>().isEmpty())
        s.commands.close()
    }

    @Test fun sendTextPresetsGoThroughChatWithPhoneSideText() = runTest {
        val s = start(chatWithHistory())
        s.send(HeadsetCommand.HelloAck(1), this)
        s.send(HeadsetCommand.SendText(bob.key, "callback"), this)
        s.send(HeadsetCommand.SendText("faction", "cu"), this)
        s.send(HeadsetCommand.SendText(bob.key, "yes"), this)
        assertEquals(listOf(bob.key to "Перезвоню", bob.key to "Да"), s.chat.sentDirect)
        assertEquals(listOf("Увидимся"), s.chat.sentFaction)
        s.commands.close()
    }

    @Test fun unknownPresetSendsNothing() = runTest {
        val s = start(chatWithHistory())
        s.send(HeadsetCommand.HelloAck(1), this)
        s.send(HeadsetCommand.SendText(bob.key, "свободный текст"), this)
        assertTrue(s.chat.sentDirect.isEmpty() && s.chat.sentFaction.isEmpty())
        s.commands.close()
    }

    @Test fun resyncRepeatsTheFullState() = runTest {
        val s = start(chatWithHistory())
        s.send(HeadsetCommand.HelloAck(1), this)
        s.take()
        s.send(HeadsetCommand.Resync, this)
        val frames = s.take()
        assertEquals(1, frames.filterIsInstance<HeadsetOut.Threads>().size)
        assertEquals(setOf("faction", bob.key), frames.filterIsInstance<HeadsetOut.Messages>().map { it.thread }.toSet())
        s.commands.close()
    }

    @Test fun historyDepthIsTwentyForDirectAndFortyForFaction() = runTest {
        val chat = FakeChat(alice.identity)
        chat.names[bob.key] = "Bob"
        repeat(50) { chat.add(bob.key, alice.key, "д$it", it * 1_000L + 1_000, callsign = "Bob") }
        repeat(60) { chat.add(bob.key, "", "ф$it", it * 1_000L + 1_000, "FACTION", callsign = "Bob") }
        val s = start(chat)
        s.send(HeadsetCommand.HelloAck(1), this)
        val messages = s.take().filterIsInstance<HeadsetOut.Messages>().associate { it.thread to it.items }
        assertEquals(20, messages.getValue(bob.key).size)
        assertEquals("д49", messages.getValue(bob.key).last().text)
        assertEquals(40, messages.getValue("faction").size)
        s.commands.close()
    }

    @Test fun statusMapping() {
        assertEquals("delivered", HeadsetMirror.statusOf(mine = false, status = MessageStatus.NONE))
        assertEquals("sent", HeadsetMirror.statusOf(mine = true, status = MessageStatus.NONE))
        assertEquals("sent", HeadsetMirror.statusOf(mine = true, status = MessageStatus.PENDING))
        assertEquals("sent", HeadsetMirror.statusOf(mine = true, status = MessageStatus.SENT))
        assertEquals("delivered", HeadsetMirror.statusOf(mine = true, status = MessageStatus.DELIVERED))
        assertEquals("delivered", HeadsetMirror.statusOf(mine = true, status = MessageStatus.READ))
    }
}
