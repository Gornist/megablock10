package com.megablok10.app.call

import android.content.Context
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.app.data.Mb10Database
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
import org.webrtc.IceCandidate

enum class CallPhase { IDLE, OUTGOING_RINGING, INCOMING_RINGING, IN_CALL }

data class CallUiState(
    val phase: CallPhase = CallPhase.IDLE,
    val callId: String = "",
    val peerPubKeyB64: String = "",
    val peerCallsign: String = "",
    /** true только когда ICE реально соединился (CONNECTED/COMPLETED) — отдельно от phase.IN_CALL, который значит лишь "обе стороны договорились созвониться". */
    val audioConnected: Boolean = false,
    val isOutgoing: Boolean = false,
    val startedAt: Long = 0L
)

/**
 * Сигнализация звонка (offer/answer/ICE/decline/end) поверх того же TCP, что
 * и чат, плюс сама медиа-сессия (CallMedia/WebRTC). Само состояние — в
 * памяти процесса, но каждый закончившийся звонок оставляет одну строку в
 * Room (call_log) — только метаданные, аудио туда не попадает.
 */
object CallManager {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(CallUiState())
    val state: StateFlow<CallUiState> = _state.asStateFlow()

    fun startOutgoingCall(context: Context, identity: Identity, peer: PeerInfo) {
        if (_state.value.phase != CallPhase.IDLE) return
        val callId = UUID.randomUUID().toString()
        _state.value = CallUiState(CallPhase.OUTGOING_RINGING, callId, peer.pubKeyB64, peer.callsign, isOutgoing = true, startedAt = System.currentTimeMillis())
        SoundPlayer.startDialTone(context)

        CallMedia.open(
            context,
            onIceCandidate = { candidate -> sendSignal(identity, peer.pubKeyB64, CallSignalType.ICE_CANDIDATE, callId, ice = candidate) },
            onConnected = { if (_state.value.callId == callId) _state.value = _state.value.copy(audioConnected = true) },
            onDisconnected = { if (_state.value.callId == callId) _state.value = _state.value.copy(audioConnected = false) }
        )
        CallMedia.addLocalAudioTrack(context)
        CallMedia.createOffer { sdp ->
            val signal = CallSignal(CallSignalType.OFFER, callId, identity.publicKeyB64, identity.callsign, peer.pubKeyB64, System.currentTimeMillis(), sdp = sdp)
            scope.launch {
                val delivered = CallClient.send(peer.host, peer.port, signal)
                if (!delivered && _state.value.callId == callId) {
                    // Не достучались до пира прямо сейчас (ушёл из сети между сканом присутствия и звонком) — откатываем вызов локально, ждать нечего.
                    endCallLocal(context, CallOutcome.UNREACHABLE)
                }
            }
        }
    }

    /** Вызывается из ChatServer.onCallSignal — сигнал уже пришёл по сети, тут только реакция на него. */
    fun onSignalReceived(context: Context, identity: Identity, signal: CallSignal) {
        when (signal.type) {
            CallSignalType.OFFER -> {
                if (_state.value.phase != CallPhase.IDLE) return // уже заняты другим звонком — молча игнорируем, без busy-сигнала в MVP
                val sdp = signal.sdp ?: return
                _state.value = CallUiState(CallPhase.INCOMING_RINGING, signal.callId, signal.fromPubKeyB64, signal.fromCallsign, isOutgoing = false, startedAt = System.currentTimeMillis())
                SoundPlayer.startIncomingRingtone(context)
                CallMedia.open(
                    context,
                    onIceCandidate = { candidate -> sendSignal(identity, signal.fromPubKeyB64, CallSignalType.ICE_CANDIDATE, signal.callId, ice = candidate) },
                    onConnected = { if (_state.value.callId == signal.callId) _state.value = _state.value.copy(audioConnected = true) },
                    onDisconnected = { if (_state.value.callId == signal.callId) _state.value = _state.value.copy(audioConnected = false) }
                )
                // Обработать чужой SDP и начать сбор своих ICE-кандидатов можно сразу — микрофон подключаем только по "Принять" (см. accept()).
                CallMedia.setRemoteOffer(sdp)
            }
            CallSignalType.ANSWER -> if (_state.value.callId == signal.callId) {
                val sdp = signal.sdp ?: return
                SoundPlayer.stopLoop()
                _state.value = _state.value.copy(phase = CallPhase.IN_CALL)
                CallMedia.setRemoteAnswer(sdp)
                CallForegroundService.start(context, _state.value.peerCallsign)
            }
            CallSignalType.ICE_CANDIDATE -> if (_state.value.callId == signal.callId) {
                val mid = signal.iceSdpMid ?: return
                val idx = signal.iceSdpMLineIndex ?: return
                val candidate = signal.iceCandidate ?: return
                CallMedia.addRemoteIceCandidate(mid, idx, candidate)
            }
            CallSignalType.DECLINE, CallSignalType.END -> if (_state.value.callId == signal.callId) {
                val outcome = when (_state.value.phase) {
                    CallPhase.IN_CALL -> CallOutcome.COMPLETED
                    CallPhase.OUTGOING_RINGING -> CallOutcome.DECLINED // пир отклонил/сбросил, пока мы дозванивались
                    CallPhase.INCOMING_RINGING -> CallOutcome.MISSED // звонивший сам передумал/сбросил, пока мы не ответили
                    CallPhase.IDLE -> CallOutcome.COMPLETED
                }
                endCallLocal(context, outcome)
            }
        }
    }

    fun accept(context: Context, identity: Identity) {
        val s = _state.value
        if (s.phase != CallPhase.INCOMING_RINGING) return
        SoundPlayer.stopLoop()
        _state.value = s.copy(phase = CallPhase.IN_CALL)
        CallMedia.addLocalAudioTrack(context)
        CallMedia.createAnswer { sdp -> sendSignal(identity, s.peerPubKeyB64, CallSignalType.ANSWER, s.callId, sdp = sdp) }
        CallForegroundService.start(context, s.peerCallsign)
    }

    /** И отклонение входящего, и отмена исходящего, и завершение уже идущего звонка — везде со стороны пира это просто "разговор закончен". */
    fun endCall(context: Context, identity: Identity) {
        val s = _state.value
        if (s.phase == CallPhase.IDLE) return
        val type = if (s.phase == CallPhase.INCOMING_RINGING) CallSignalType.DECLINE else CallSignalType.END
        sendSignal(identity, s.peerPubKeyB64, type, s.callId)
        val outcome = when (s.phase) {
            CallPhase.IN_CALL -> CallOutcome.COMPLETED
            CallPhase.OUTGOING_RINGING -> CallOutcome.CANCELLED
            CallPhase.INCOMING_RINGING -> CallOutcome.DECLINED
            CallPhase.IDLE -> CallOutcome.COMPLETED
        }
        endCallLocal(context, outcome)
    }

    private fun sendSignal(identity: Identity, peerPubKeyB64: String, type: CallSignalType, callId: String, sdp: String? = null, ice: IceCandidate? = null) {
        val peer = PresenceService.peers.value.find { it.pubKeyB64 == peerPubKeyB64 } ?: return
        val signal = CallSignal(
            type = type, callId = callId, fromPubKeyB64 = identity.publicKeyB64, fromCallsign = identity.callsign,
            toPubKeyB64 = peerPubKeyB64, timestamp = System.currentTimeMillis(), sdp = sdp,
            iceSdpMid = ice?.sdpMid, iceSdpMLineIndex = ice?.sdpMLineIndex, iceCandidate = ice?.sdp
        )
        scope.launch { CallClient.send(peer.host, peer.port, signal) }
    }

    private fun endCallLocal(context: Context, outcome: String) {
        val s = _state.value
        SoundPlayer.stopLoop()
        CallMedia.close()
        CallForegroundService.stop(context)
        _state.value = CallUiState()

        if (s.phase == CallPhase.IDLE) return // нечего логировать — звонка и не было
        val appContext = context.applicationContext
        val endedAt = System.currentTimeMillis()
        scope.launch {
            Mb10Database.get(appContext).callLogDao().insert(
                CallLogEntity(
                    peerPubKeyB64 = s.peerPubKeyB64,
                    peerCallsign = s.peerCallsign,
                    direction = if (s.isOutgoing) CallDirection.OUTGOING else CallDirection.INCOMING,
                    outcome = outcome,
                    startedAt = s.startedAt,
                    endedAt = endedAt
                )
            )
        }
    }
}
