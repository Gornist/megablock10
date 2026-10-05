package com.megablok10.app.headset

import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.app.identity.Identity
import com.megablok10.app.testing.FakeCallControls
import com.megablok10.app.testing.TestPlayer
import com.megablok10.kit.mesh.OnlinePlayer
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
import org.junit.Assert.assertTrue
import org.junit.Test

/** Звонки в очках: кадры `call` и `call_log`, команды accept/decline/hangup/mute/start_call (на фейках, как кнопки на экране телефона). */
@OptIn(ExperimentalCoroutinesApi::class)
class HeadsetCallsTest {
    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")

    private fun state(phase: CallPhase, since: Long = 5_000, muted: Boolean = false) =
        CallUiState(phase = phase, callId = "c1", peerPubKeyB64 = bob.key, peerCallsign = "Bob", startedAt = 1_000, phaseSince = since, muted = muted)

    private fun log(direction: String, outcome: String, start: Long = 10_000, end: Long = 70_000) =
        CallLogEntity(peerPubKeyB64 = bob.key, peerCallsign = "Bob", direction = direction, outcome = outcome, startedAt = start, endedAt = end)

    // ---- маппинг ----

    @Test fun phasesMapToTheAgreedNamesAndSecondsSincePhaseStart() {
        assertEquals(HeadsetCall("idle", "", 0, false), callFrame(CallUiState()))
        assertEquals(HeadsetCall("outgoing", "Bob", 5, false), callFrame(state(CallPhase.OUTGOING_RINGING)))
        assertEquals(HeadsetCall("incoming", "Bob", 5, false), callFrame(state(CallPhase.INCOMING_RINGING)))
        assertEquals(HeadsetCall("in_call", "Bob", 7, true), callFrame(state(CallPhase.IN_CALL, since = 7_500, muted = true)))
    }

    @Test fun callLogDirectionsAndDurations() {
        val items = callLogItems(
            listOf(
                log(CallDirection.INCOMING, CallOutcome.MISSED),
                log(CallDirection.INCOMING, CallOutcome.COMPLETED),
                log(CallDirection.OUTGOING, CallOutcome.COMPLETED),
                log(CallDirection.OUTGOING, CallOutcome.UNREACHABLE),
                log(CallDirection.INCOMING, CallOutcome.DECLINED),
                log(CallDirection.OUTGOING, CallOutcome.LOST),
            )
        )
        assertEquals(listOf("missed", "in", "out", "out", "in", "out"), items.map { it.dir })
        assertEquals(listOf(0L, 60L, 60L, 0L, 0L, 60L), items.map { it.durationS })
        assertEquals(10L, items.first().ts)
        assertEquals("Bob", items.first().peer)
    }

    @Test fun callLogIsCutToTwentyNewestFirst() {
        val many = (1..30).map { log(CallDirection.OUTGOING, CallOutcome.COMPLETED, start = it * 1_000L, end = it * 1_000L + 1_000) }
        val items = callLogItems(many)
        assertEquals(20, items.size)
        assertEquals(1L, items.first().ts)
    }

    // ---- команды через зеркало ----

    private class EmptyChat(val me: Identity) : HeadsetChatPort {
        override fun changes(me: Identity): Flow<Unit> = MutableStateFlow(0).map { }
        override suspend fun directPeers(me: String) = emptyList<String>()
        override suspend fun recentDirect(me: String, peerPubKey: String, limit: Int) = emptyList<com.megablok10.app.data.ChatMessageEntity>()
        override suspend fun recentFaction(faction: String, limit: Int) = emptyList<com.megablok10.app.data.ChatMessageEntity>()
        override suspend fun peerCallsign(pubKey: String): String? = null
        override suspend fun sendDirect(identity: Identity, peerPubKeyB64: String, text: String) = true
        override suspend fun sendFaction(identity: Identity, text: String) = Unit
        override fun contacts(): Flow<List<HeadsetContact>> = MutableStateFlow(emptyList())
    }

    private class NoRead : HeadsetReadState {
        override fun lastRead(thread: String): Long? = null
        override fun setLastRead(thread: String, upToMs: Long) = Unit
    }

    private class Session(val calls: FakeCallControls) {
        val frames = mutableListOf<HeadsetOut>()
        val commands = Channel<HeadsetCommand>(Channel.UNLIMITED)
        fun take(): List<HeadsetOut> = frames.toList().also { frames.clear() }
    }

    private fun TestScope.start(
        calls: FakeCallControls,
        online: List<OnlinePlayer> = listOf(bob.peer),
        mic: Boolean = true,
    ): Session {
        val s = Session(calls)
        val bridge = HeadsetCallBridge(calls, { online }, { mic })
        val mirror = HeadsetMirror(EmptyChat(alice.identity), { alice.identity }, NoRead(), callBridge = bridge)
        launch { mirror.serve({ f -> s.frames += f; true }, s.commands) }
        runCurrent()
        return s
    }

    private suspend fun Session.cmd(c: HeadsetCommand, scope: TestScope) { commands.send(c); scope.runCurrent() }

    @Test fun afterAckCurrentCallAndLogAreSentAndChangesFollow() = runTest {
        val calls = FakeCallControls()
        calls.log.value = listOf(log(CallDirection.INCOMING, CallOutcome.MISSED))
        val s = start(calls)
        s.take()
        s.cmd(HeadsetCommand.HelloAck(1), this)
        val first = s.take()
        assertEquals(HeadsetCall("idle", "", 0, false), first.filterIsInstance<HeadsetOut.Call>().single().call)
        assertEquals("missed", first.filterIsInstance<HeadsetOut.CallLog>().single().items.single().dir)

        calls.state.value = state(CallPhase.INCOMING_RINGING)
        runCurrent()
        assertEquals("incoming", s.take().filterIsInstance<HeadsetOut.Call>().single().call.phase)
        calls.state.value = state(CallPhase.INCOMING_RINGING) // то же самое — повтора нет
        runCurrent()
        assertTrue(s.take().filterIsInstance<HeadsetOut.Call>().isEmpty())
        s.commands.close()
    }

    @Test fun resyncSendsCallAndLogAgain() = runTest {
        val calls = FakeCallControls(state(CallPhase.IN_CALL))
        val s = start(calls)
        s.cmd(HeadsetCommand.HelloAck(1), this)
        s.take()
        s.cmd(HeadsetCommand.Resync, this)
        val frames = s.take()
        assertEquals("in_call", frames.filterIsInstance<HeadsetOut.Call>().single().call.phase)
        assertEquals(1, frames.filterIsInstance<HeadsetOut.CallLog>().size)
        s.commands.close()
    }

    @Test fun acceptAndDeclineOnlyWorkOnIncomingCall() = runTest {
        val calls = FakeCallControls(state(CallPhase.IN_CALL))
        val s = start(calls)
        s.cmd(HeadsetCommand.HelloAck(1), this)
        s.cmd(HeadsetCommand.Accept, this)
        s.cmd(HeadsetCommand.Decline, this)
        assertEquals("в разговоре принимать и отклонять нечего", 0, calls.accepted + calls.ended)
        calls.state.value = state(CallPhase.INCOMING_RINGING)
        runCurrent()
        s.cmd(HeadsetCommand.Accept, this)
        assertEquals(1, calls.accepted)
        s.cmd(HeadsetCommand.Decline, this)
        assertEquals(1, calls.ended)
        s.commands.close()
    }

    @Test fun hangupWorksForOutgoingAndInCallButNotForIncoming() = runTest {
        val calls = FakeCallControls(state(CallPhase.INCOMING_RINGING))
        val s = start(calls)
        s.cmd(HeadsetCommand.HelloAck(1), this)
        s.cmd(HeadsetCommand.Hangup, this)
        assertEquals("входящий отклоняют командой decline", 0, calls.ended)
        calls.state.value = state(CallPhase.OUTGOING_RINGING)
        runCurrent()
        s.cmd(HeadsetCommand.Hangup, this)
        calls.state.value = state(CallPhase.IN_CALL)
        runCurrent()
        s.cmd(HeadsetCommand.Hangup, this)
        assertEquals(2, calls.ended)
        s.commands.close()
    }

    @Test fun muteIsPassedToTheCall() = runTest {
        val calls = FakeCallControls(state(CallPhase.IN_CALL))
        val s = start(calls)
        s.cmd(HeadsetCommand.HelloAck(1), this)
        s.cmd(HeadsetCommand.Mute(true), this)
        s.cmd(HeadsetCommand.Mute(false), this)
        assertEquals(listOf(true, false), calls.muteCalls)
        s.commands.close()
    }

    @Test fun startCallDialsAVisiblePlayerOnlyWhenIdle() = runTest {
        val calls = FakeCallControls()
        val s = start(calls)
        s.cmd(HeadsetCommand.HelloAck(1), this)
        s.cmd(HeadsetCommand.StartCall("Bob"), this)
        assertEquals(listOf(bob.peer), calls.started)
        s.cmd(HeadsetCommand.StartCall("Nobody"), this)
        assertEquals("не видно в сети — не набираем", 1, calls.started.size)
        calls.state.value = state(CallPhase.IN_CALL)
        runCurrent()
        s.cmd(HeadsetCommand.StartCall("Bob"), this)
        assertEquals("уже в звонке — не набираем", 1, calls.started.size)
        s.commands.close()
    }

    @Test fun withoutMicrophonePermissionAcceptAndStartAreRefused() = runTest {
        val calls = FakeCallControls(state(CallPhase.INCOMING_RINGING))
        val s = start(calls, mic = false)
        s.cmd(HeadsetCommand.HelloAck(1), this)
        s.cmd(HeadsetCommand.Accept, this)
        assertEquals(0, calls.accepted)
        s.cmd(HeadsetCommand.Decline, this)
        assertEquals("отклонить можно и без микрофона", 1, calls.ended)
        calls.state.value = CallUiState()
        runCurrent()
        s.cmd(HeadsetCommand.StartCall("Bob"), this)
        assertTrue(calls.started.isEmpty())
        s.commands.close()
    }

    @Test fun mirrorWithoutBridgeStaysSilentAboutCalls() = runTest {
        val chat = EmptyChat(alice.identity)
        val frames = mutableListOf<HeadsetOut>()
        val cmds = Channel<HeadsetCommand>(Channel.UNLIMITED)
        launch { HeadsetMirror(chat, { alice.identity }, NoRead()).serve({ frames += it; true }, cmds) }
        runCurrent()
        cmds.send(HeadsetCommand.HelloAck(1)); runCurrent()
        cmds.send(HeadsetCommand.Accept); runCurrent()
        assertTrue(frames.none { it is HeadsetOut.Call || it is HeadsetOut.CallLog })
        cmds.close()
    }
}
