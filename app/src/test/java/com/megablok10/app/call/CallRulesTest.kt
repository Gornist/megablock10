package com.megablok10.app.call

import com.megablok10.app.data.CallOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class CallRulesTest {
    private fun signal(type: CallSignalType, callId: String = "call-1", from: String = "bob") =
        CallSignal(type, callId, from, "Боб", "alice", 1L, sdp = "sdp")

    private fun state(phase: CallPhase, callId: String = "call-1", peer: String = "bob") =
        CallUiState(phase, callId, peer, "Боб", isOutgoing = phase == CallPhase.OUTGOING_RINGING, startedAt = 100L)

    @Test fun userHangUpDeclinesIncomingCancelsOutgoingAndCompletesRunningCall() {
        assertEquals(CallRules.HangUp(CallSignalType.DECLINE, CallOutcome.DECLINED), CallRules.hangUpByUser(CallPhase.INCOMING_RINGING))
        assertEquals(CallRules.HangUp(CallSignalType.END, CallOutcome.CANCELLED), CallRules.hangUpByUser(CallPhase.OUTGOING_RINGING))
        assertEquals(CallRules.HangUp(CallSignalType.END, CallOutcome.COMPLETED), CallRules.hangUpByUser(CallPhase.IN_CALL))
    }

    @Test fun peerHangUpOutcomeDependsOnThePhaseItCaughtUsIn() {
        assertEquals(CallOutcome.COMPLETED, CallRules.outcomeOfPeerHangUp(CallPhase.IN_CALL))
        assertEquals(CallOutcome.DECLINED, CallRules.outcomeOfPeerHangUp(CallPhase.OUTGOING_RINGING))
        assertEquals(CallOutcome.MISSED, CallRules.outcomeOfPeerHangUp(CallPhase.INCOMING_RINGING))
    }

    @Test fun ringTimeoutEndsOnlyACallThatIsStillRinging() {
        assertEquals(CallRules.RingTimeout.SendEndAndFinish(CallOutcome.UNREACHABLE), CallRules.onRingTimeout(CallPhase.OUTGOING_RINGING))
        assertEquals(CallRules.RingTimeout.Finish(CallOutcome.MISSED), CallRules.onRingTimeout(CallPhase.INCOMING_RINGING))
        assertEquals(CallRules.RingTimeout.Ignore, CallRules.onRingTimeout(CallPhase.IN_CALL))
        assertEquals(CallRules.RingTimeout.Ignore, CallRules.onRingTimeout(CallPhase.IDLE))
    }

    @Test fun offerWhileFreeStartsRinging() {
        assertEquals(CallRules.OfferAction.RING, CallRules.onOffer(CallUiState(), signal(CallSignalType.OFFER)))
    }

    @Test fun offerWhileBusyWithAnotherCallIsIgnored() {
        for (phase in listOf(CallPhase.OUTGOING_RINGING, CallPhase.INCOMING_RINGING, CallPhase.IN_CALL)) {
            assertEquals(phase.name, CallRules.OfferAction.IGNORE_BUSY, CallRules.onOffer(state(phase, callId = "other"), signal(CallSignalType.OFFER)))
        }
    }

    @Test fun repeatedOfferOfTheRunningCallFromTheSamePeerRestartsIceInsteadOfRinging() {
        val running = state(CallPhase.IN_CALL)
        assertEquals(CallRules.OfferAction.RESTART_ICE, CallRules.onOffer(running, signal(CallSignalType.OFFER)))
        // тот же callId, но от другого ключа или до ответа (ещё звонит) — не перезапуск
        assertEquals(CallRules.OfferAction.IGNORE_BUSY, CallRules.onOffer(running, signal(CallSignalType.OFFER, from = "mallory")))
        assertEquals(CallRules.OfferAction.IGNORE_BUSY, CallRules.onOffer(state(CallPhase.INCOMING_RINGING), signal(CallSignalType.OFFER)))
    }

    @Test fun secondAnswerOfARunningCallOnlyAppliesTheRestartAnswer() {
        assertEquals(CallRules.AnswerAction.START_CALL, CallRules.onAnswer(state(CallPhase.OUTGOING_RINGING)))
        assertEquals(CallRules.AnswerAction.APPLY_RESTART_ANSWER, CallRules.onAnswer(state(CallPhase.IN_CALL)))
    }

    @Test fun signalsOfAnotherCallDoNotBelongToTheCurrentOne() {
        val current = state(CallPhase.IN_CALL, callId = "call-1")
        assertTrue(CallRules.belongsToCurrentCall(current, signal(CallSignalType.END, callId = "call-1")))
        assertFalse(CallRules.belongsToCurrentCall(current, signal(CallSignalType.END, callId = "call-2")))
        assertFalse(CallRules.belongsToCurrentCall(CallUiState(), signal(CallSignalType.END)))
    }

    @Test fun iceIsRestartedOnlyInARunningCallOfTheSameId() {
        assertTrue(CallRules.canRestartIce(state(CallPhase.IN_CALL), "call-1"))
        assertFalse(CallRules.canRestartIce(state(CallPhase.IN_CALL), "call-2"))
        assertFalse(CallRules.canRestartIce(state(CallPhase.OUTGOING_RINGING), "call-1"))
        assertFalse(CallRules.canRestartIce(CallUiState(), "call-1"))
    }

    @Test fun newCallsStartInRingingPhasesWithTheirDirection() {
        val out = CallRules.outgoing("c", "bob", "Боб", 5L)
        assertEquals(CallPhase.OUTGOING_RINGING, out.phase)
        assertTrue(out.isOutgoing)
        assertEquals(5L, out.startedAt)
        assertEquals(5L, out.phaseSince)
        val inc = CallRules.incoming("c", "bob", "Боб", 6L)
        assertEquals(CallPhase.INCOMING_RINGING, inc.phase)
        assertFalse(inc.isOutgoing)
        assertEquals("Боб", inc.peerCallsign)
    }

    @Test fun connectionFlagsTrackTheCallAndRememberThatItEverConnected() {
        val ringing = state(CallPhase.IN_CALL)
        val up = CallRules.withConnected(ringing, "call-1", true)
        assertTrue(up.audioConnected)
        assertTrue(up.everConnected)
        val lost = CallRules.withConnected(up, "call-1", false)
        assertFalse(lost.audioConnected)
        assertTrue("после потери связи everConnected остаётся — это «восстанавливаем», а не «соединяемся»", lost.everConnected)
    }

    @Test fun connectionEventOfAnotherOrFinishedCallChangesNothing() {
        val running = state(CallPhase.IN_CALL)
        assertSame(running, CallRules.withConnected(running, "other", true))
        val idle = CallUiState()
        assertSame(idle, CallRules.withConnected(idle, "call-1", true))
    }

    @Test fun answeringStartsTheConversationPhaseAtTheMomentOfAnswerKeepingTheStartOfTheCall() {
        val s = CallRules.inCall(state(CallPhase.INCOMING_RINGING), 900L)
        assertEquals(CallPhase.IN_CALL, s.phase)
        assertEquals(900L, s.phaseSince)
        assertEquals(100L, s.startedAt)
    }

    @Test fun muteChangesOnlyARunningCallAndOnlyToADifferentValue() {
        val running = state(CallPhase.IN_CALL)
        assertTrue(CallRules.withMuted(running, true)!!.muted)
        assertNull("то же значение — ничего не менять", CallRules.withMuted(running, false))
        assertNull(CallRules.withMuted(state(CallPhase.OUTGOING_RINGING), true))
        assertNull(CallRules.withMuted(CallUiState(), true))
    }
}
