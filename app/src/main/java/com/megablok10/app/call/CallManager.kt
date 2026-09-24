package com.megablok10.app.call

import android.content.Context
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.identity.Identity
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.sound.SoundPlayer
import com.megablok10.app.log.Mb10Log
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.delay
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
private const val RING_TIMEOUT_MS = 45_000L

private const val TAG = "CallManager"

/** `candidate:<foundation> <component> udp|tcp <priority> <address> <port> typ host|srflx|relay|prflx ...` (RFC 5245). */
private val ICE_CANDIDATE_PATTERN = Regex("""candidate:\S+ \d+ (\S+) \d+ (\S+) \d+ typ (\S+)""")

object CallManager {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(CallUiState())
    val state: StateFlow<CallUiState> = _state.asStateFlow()

    fun startOutgoingCall(context: Context, identity: Identity, peer: PeerInfo) {
        if (_state.value.phase != CallPhase.IDLE) return
        val callId = UUID.randomUUID().toString()
        Mb10Log.event(TAG, "call.outgoing_start", "call" to callId.take(8), "peer" to Mb10Log.short(peer.pubKeyB64), "addr" to "${peer.host}:${peer.port}")
        _state.value = CallUiState(CallPhase.OUTGOING_RINGING, callId, peer.pubKeyB64, peer.callsign, isOutgoing = true, startedAt = System.currentTimeMillis())
        SoundPlayer.startDialTone(context)

        CallMedia.open(
            context,
            onIceCandidate = { candidate -> sendSignal(identity, peer.pubKeyB64, CallSignalType.ICE_CANDIDATE, callId, ice = candidate) },
            onConnected = { if (_state.value.callId == callId) _state.value = _state.value.copy(audioConnected = true) },
            onDisconnected = { if (_state.value.callId == callId) _state.value = _state.value.copy(audioConnected = false) }
        )
        CallMedia.addLocalAudioTrack(context)
        scheduleRingTimeout(context, identity, callId)
        CallMedia.createOffer { sdp ->
            // Звонок могли отменить, пока WebRTC собирал offer — не отправляем его "вдогонку" END,
            // иначе у собеседника вызов оживает уже после отмены и звонит, пока его не сбросят вручную.
            if (_state.value.callId != callId) return@createOffer
            val signal = CallSignal(CallSignalType.OFFER, callId, identity.publicKeyB64, identity.callsign, peer.pubKeyB64, System.currentTimeMillis(), sdp = sdp)
            scope.launch {
                val delivered = CallClient.send(peer.host, peer.port, signal)
                Mb10Log.event(TAG, "call.offer_sent", "call" to callId.take(8), "delivered" to delivered)
                if (!delivered && _state.value.callId == callId) {
                    // Не достучались до пира прямо сейчас (ушёл из сети между сканом присутствия и звонком) — откатываем вызов локально, ждать нечего.
                    endCallLocal(context, CallOutcome.UNREACHABLE)
                }
            }
        }
    }

    /** Вызывается из ChatServer.onCallSignal — сигнал уже пришёл по сети, тут только реакция на него. */
    fun onSignalReceived(context: Context, identity: Identity, signal: CallSignal) {
        Mb10Log.event(TAG, "call.signal_in", "type" to signal.type.name, "call" to signal.callId.take(8), "from" to Mb10Log.short(signal.fromPubKeyB64), "phase" to _state.value.phase.name)
        when (signal.type) {
            CallSignalType.OFFER -> {
                if (_state.value.phase != CallPhase.IDLE) { Mb10Log.warnEvent(TAG, "call.offer_ignored_busy", "call" to signal.callId.take(8)); return } // уже заняты другим звонком — молча игнорируем, без busy-сигнала в MVP
                val sdp = signal.sdp ?: return
                _state.value = CallUiState(CallPhase.INCOMING_RINGING, signal.callId, signal.fromPubKeyB64, signal.fromCallsign, isOutgoing = false, startedAt = System.currentTimeMillis())
                SoundPlayer.startIncomingRingtone(context)
                scheduleRingTimeout(context, identity, signal.callId)
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
                Mb10Log.d(TAG, "call.ice_candidate_in call=${signal.callId.take(8)} ${iceCandidateSummary(candidate)}")
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
        Mb10Log.event(TAG, "call.accept", "call" to s.callId.take(8))
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
        Mb10Log.event(TAG, "call.end_by_user", "call" to s.callId.take(8), "phase" to s.phase.name)
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

    /**
     * Вызов без ответа не должен висеть вечно: если звонящий пропал (приложение убито, вышел из
     * сети), у получателя рингтон иначе звонил бы бесконечно, а у звонящего "звонок" не кончался.
     */
    private fun scheduleRingTimeout(context: Context, identity: Identity, callId: String) {
        scope.launch {
            delay(RING_TIMEOUT_MS)
            val s = _state.value
            if (s.callId != callId) return@launch
            when (s.phase) {
                CallPhase.OUTGOING_RINGING -> {
                    sendSignal(identity, s.peerPubKeyB64, CallSignalType.END, callId)
                    endCallLocal(context, CallOutcome.UNREACHABLE)
                }
                CallPhase.INCOMING_RINGING -> endCallLocal(context, CallOutcome.MISSED)
                else -> Unit
            }
        }
    }

    private fun sendSignal(identity: Identity, peerPubKeyB64: String, type: CallSignalType, callId: String, sdp: String? = null, ice: IceCandidate? = null) {
        val peer = PresenceService.peers.value.find { it.pubKeyB64 == peerPubKeyB64 } ?: run {
            Mb10Log.warnEvent(TAG, "call.signal_dropped_peer_unknown", "type" to type.name, "call" to callId.take(8), "peer" to Mb10Log.short(peerPubKeyB64))
            return
        }
        val signal = CallSignal(
            type = type, callId = callId, fromPubKeyB64 = identity.publicKeyB64, fromCallsign = identity.callsign,
            toPubKeyB64 = peerPubKeyB64, timestamp = System.currentTimeMillis(), sdp = sdp,
            iceSdpMid = ice?.sdpMid, iceSdpMLineIndex = ice?.sdpMLineIndex, iceCandidate = ice?.sdp
        )
        scope.launch {
            val ok = CallClient.send(peer.host, peer.port, signal)
            if (type == CallSignalType.ICE_CANDIDATE) {
                // Раньше успешная отправка кандидата не логировалась вовсе (только отказ) — не видно было даже, сколько их вообще
                // ушло. На разборе живой проверки это как раз и не хватило: по логам нельзя было отличить «кандидат не сгенерировался»
                // от «сгенерировался, но не долетел». Debug-уровень — их может быть много за один звонок.
                Mb10Log.d(TAG, "call.ice_candidate_out call=${callId.take(8)} delivered=$ok ${ice?.sdp?.let(::iceCandidateSummary) ?: ""}")
            } else {
                Mb10Log.event(TAG, "call.signal_out", "type" to type.name, "call" to callId.take(8), "delivered" to ok)
            }
        }
    }

    /** `typ host 192.168.1.49` из строки ICE-кандидата (RFC 5245) — для диагностики, без полной строки (в ней ufrag/pwd). */
    private fun iceCandidateSummary(candidateSdp: String): String {
        val m = ICE_CANDIDATE_PATTERN.find(candidateSdp) ?: return "candidate=?"
        return "transport=${m.groupValues[1]} addr=${m.groupValues[2]} typ=${m.groupValues[3]}"
    }

    private fun endCallLocal(context: Context, outcome: String) {
        val s = _state.value
        Mb10Log.event(TAG, "call.ended", "call" to s.callId.take(8), "outcome" to outcome, "phase" to s.phase.name, "durationMs" to (System.currentTimeMillis() - s.startedAt))
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
