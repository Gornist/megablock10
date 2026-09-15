package com.megablok10.app.call

import android.content.Context
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.sound.SoundPlayer
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class CallPhase { IDLE, OUTGOING_RINGING, INCOMING_RINGING, IN_CALL }

data class CallUiState(
    val phase: CallPhase = CallPhase.IDLE,
    val callId: String = "",
    val peerPubKeyB64: String = "",
    val peerCallsign: String = ""
)

/**
 * Только сигнализация звонка (offer/answer/decline/end) поверх того же TCP,
 * что и чат — состояние держится в памяти процесса, ни один звонок никуда не
 * пишется в Room. Собственно голосовой поток (WebRTC) — следующий этап,
 * здесь его сознательно нет: IN_CALL значит только то, что обе стороны
 * согласились на звонок, а не то, что звук уже передаётся.
 */
object CallManager {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(CallUiState())
    val state: StateFlow<CallUiState> = _state.asStateFlow()

    fun startOutgoingCall(context: Context, identity: Identity, peer: PeerInfo) {
        if (_state.value.phase != CallPhase.IDLE) return
        val callId = UUID.randomUUID().toString()
        _state.value = CallUiState(CallPhase.OUTGOING_RINGING, callId, peer.pubKeyB64, peer.callsign)
        SoundPlayer.startDialTone(context)
        val signal = CallSignal(CallSignalType.OFFER, callId, identity.publicKeyB64, identity.callsign, peer.pubKeyB64, System.currentTimeMillis())
        scope.launch {
            val delivered = CallClient.send(peer.host, peer.port, signal)
            if (!delivered && _state.value.callId == callId) {
                // Не достучались до пира прямо сейчас (ушёл из сети между сканом присутствия и звонком) — откатываем вызов локально, ждать нечего.
                endCallLocal()
            }
        }
    }

    /** Вызывается из ChatServer.onCallSignal — сигнал уже пришёл по сети, тут только реакция на него. */
    fun onSignalReceived(context: Context, signal: CallSignal) {
        when (signal.type) {
            CallSignalType.OFFER -> {
                if (_state.value.phase != CallPhase.IDLE) return // уже заняты другим звонком — молча игнорируем, без busy-сигнала в MVP
                _state.value = CallUiState(CallPhase.INCOMING_RINGING, signal.callId, signal.fromPubKeyB64, signal.fromCallsign)
                SoundPlayer.startIncomingRingtone(context)
            }
            CallSignalType.ANSWER -> if (_state.value.callId == signal.callId) {
                SoundPlayer.stopLoop()
                _state.value = _state.value.copy(phase = CallPhase.IN_CALL)
            }
            CallSignalType.DECLINE, CallSignalType.END -> if (_state.value.callId == signal.callId) {
                endCallLocal()
            }
        }
    }

    fun accept(context: Context, identity: Identity) {
        val s = _state.value
        if (s.phase != CallPhase.INCOMING_RINGING) return
        SoundPlayer.stopLoop()
        _state.value = s.copy(phase = CallPhase.IN_CALL)
        sendSignalToPeer(identity, CallSignalType.ANSWER, s)
    }

    /** И отклонение входящего, и отмена исходящего, и завершение уже идущего звонка — везде со стороны пира это просто "разговор закончен". */
    fun endCall(identity: Identity) {
        val s = _state.value
        if (s.phase == CallPhase.IDLE) return
        val type = if (s.phase == CallPhase.INCOMING_RINGING) CallSignalType.DECLINE else CallSignalType.END
        sendSignalToPeer(identity, type, s)
        endCallLocal()
    }

    private fun sendSignalToPeer(identity: Identity, type: CallSignalType, s: CallUiState) {
        val peer = PresenceService.peers.value.find { it.pubKeyB64 == s.peerPubKeyB64 } ?: return
        val signal = CallSignal(type, s.callId, identity.publicKeyB64, identity.callsign, s.peerPubKeyB64, System.currentTimeMillis())
        scope.launch { CallClient.send(peer.host, peer.port, signal) }
    }

    private fun endCallLocal() {
        SoundPlayer.stopLoop()
        _state.value = CallUiState()
    }
}
