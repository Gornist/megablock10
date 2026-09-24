package com.megablok10.app.call

import android.content.Context
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogDao
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.app.identity.Identity
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.net.LineSocketClient
import com.megablok10.app.sound.SoundPlayer
import com.megablok10.app.log.Mb10Log
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
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

class CallManager(
    private val app: Context,
    private val peers: () -> List<PeerInfo>,
    private val callLog: CallLogDao,
    private val lines: LineSocketClient,
) : CallControls {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(CallUiState())
    override val state: StateFlow<CallUiState> = _state.asStateFlow()

    /** Журнал звонков (call_log): одна строка на каждый закончившийся звонок, новые сверху. */
    override fun observeLog(): Flow<List<CallLogEntity>> = callLog.observeAll()

    override fun startOutgoingCall(identity: Identity, peer: PeerInfo) {
        if (_state.value.phase != CallPhase.IDLE) return
        val callId = UUID.randomUUID().toString()
        Mb10Log.event(TAG, "call.outgoing_start", "call" to callId.take(8), "peer" to Mb10Log.short(peer.pubKeyB64), "addr" to "${peer.host}:${peer.port}")
        _state.value = CallUiState(CallPhase.OUTGOING_RINGING, callId, peer.pubKeyB64, peer.callsign, isOutgoing = true, startedAt = System.currentTimeMillis())
        SoundPlayer.startDialTone(app)

        CallMedia.open(
            app,
            onIceCandidate = { candidate -> sendSignal(identity, peer.pubKeyB64, CallSignalType.ICE_CANDIDATE, callId, ice = candidate) },
            onConnected = { if (_state.value.callId == callId) _state.value = _state.value.copy(audioConnected = true) },
            onDisconnected = { if (_state.value.callId == callId) _state.value = _state.value.copy(audioConnected = false) }
        )
        CallMedia.addLocalAudioTrack(app)
        scheduleRingTimeout(identity, callId)
        CallMedia.createOffer { sdp ->
            // Звонок могли отменить, пока WebRTC собирал offer — не отправляем его "вдогонку" END,
            // иначе у собеседника вызов оживает уже после отмены и звонит, пока его не сбросят вручную.
            if (_state.value.callId != callId) return@createOffer
            val signal = CallSignal(CallSignalType.OFFER, callId, identity.publicKeyB64, identity.callsign, peer.pubKeyB64, System.currentTimeMillis(), sdp = sdp)
            scope.launch {
                val delivered = lines.sendLine(peer.host, peer.port, CallProtocol.encode(signal))
                Mb10Log.event(TAG, "call.offer_sent", "call" to callId.take(8), "delivered" to delivered)
                if (!delivered && _state.value.callId == callId) {
                    // Не достучались до пира прямо сейчас (ушёл из сети между сканом присутствия и звонком) — откатываем вызов локально, ждать нечего.
                    endCallLocal(CallOutcome.UNREACHABLE)
                }
            }
        }
    }

    /** Вызывается из ChatServer.onCallSignal — сигнал уже пришёл по сети, тут только реакция на него. */
    fun onSignalReceived(identity: Identity, signal: CallSignal) {
        Mb10Log.event(TAG, "call.signal_in", "type" to signal.type.name, "call" to signal.callId.take(8), "from" to Mb10Log.short(signal.fromPubKeyB64), "phase" to _state.value.phase.name)
        when (signal.type) {
            CallSignalType.OFFER -> onOffer(identity, signal)
            CallSignalType.ANSWER -> if (_state.value.callId == signal.callId) onAnswer(signal)
            CallSignalType.ICE_CANDIDATE -> if (_state.value.callId == signal.callId) onRemoteIceCandidate(signal)
            CallSignalType.DECLINE, CallSignalType.END -> if (_state.value.callId == signal.callId) onHangUpByPeer()
        }
    }

    private fun onOffer(identity: Identity, signal: CallSignal) {
        if (_state.value.phase != CallPhase.IDLE) { Mb10Log.warnEvent(TAG, "call.offer_ignored_busy", "call" to signal.callId.take(8)); return } // уже заняты другим звонком — молча игнорируем, без busy-сигнала в MVP
        val sdp = signal.sdp ?: return
        _state.value = CallUiState(CallPhase.INCOMING_RINGING, signal.callId, signal.fromPubKeyB64, signal.fromCallsign, isOutgoing = false, startedAt = System.currentTimeMillis())
        SoundPlayer.startIncomingRingtone(app)
        scheduleRingTimeout(identity, signal.callId)
        CallMedia.open(
            app,
            onIceCandidate = { candidate -> sendSignal(identity, signal.fromPubKeyB64, CallSignalType.ICE_CANDIDATE, signal.callId, ice = candidate) },
            onConnected = { if (_state.value.callId == signal.callId) _state.value = _state.value.copy(audioConnected = true) },
            onDisconnected = { if (_state.value.callId == signal.callId) _state.value = _state.value.copy(audioConnected = false) }
        )
        // Обработать чужой SDP и начать сбор своих ICE-кандидатов можно сразу — микрофон подключаем только по "Принять" (см. accept()).
        CallMedia.setRemoteOffer(sdp)
    }

    private fun onAnswer(signal: CallSignal) {
        val sdp = signal.sdp ?: return
        SoundPlayer.stopLoop()
        _state.value = _state.value.copy(phase = CallPhase.IN_CALL)
        CallMedia.setRemoteAnswer(sdp)
        CallForegroundService.start(app, _state.value.peerCallsign)
    }

    private fun onRemoteIceCandidate(signal: CallSignal) {
        val mid = signal.iceSdpMid ?: return
        val idx = signal.iceSdpMLineIndex ?: return
        val candidate = signal.iceCandidate ?: return
        Mb10Log.d(TAG, "call.ice_candidate_in call=${signal.callId.take(8)} ${iceCandidateSummary(candidate)}")
        CallMedia.addRemoteIceCandidate(mid, idx, candidate)
    }

    /** Пир отклонил или завершил звонок — исход зависит от того, на какой фазе это случилось. */
    private fun onHangUpByPeer() {
        val outcome = when (_state.value.phase) {
            CallPhase.IN_CALL -> CallOutcome.COMPLETED
            CallPhase.OUTGOING_RINGING -> CallOutcome.DECLINED // пир отклонил/сбросил, пока мы дозванивались
            CallPhase.INCOMING_RINGING -> CallOutcome.MISSED // звонивший сам передумал/сбросил, пока мы не ответили
            CallPhase.IDLE -> CallOutcome.COMPLETED
        }
        endCallLocal(outcome)
    }

    override fun accept(identity: Identity) {
        val s = _state.value
        if (s.phase != CallPhase.INCOMING_RINGING) return
        Mb10Log.event(TAG, "call.accept", "call" to s.callId.take(8))
        SoundPlayer.stopLoop()
        _state.value = s.copy(phase = CallPhase.IN_CALL)
        CallMedia.addLocalAudioTrack(app)
        CallMedia.createAnswer { sdp -> sendSignal(identity, s.peerPubKeyB64, CallSignalType.ANSWER, s.callId, sdp = sdp) }
        CallForegroundService.start(app, s.peerCallsign)
    }

    /** И отклонение входящего, и отмена исходящего, и завершение уже идущего звонка — везде со стороны пира это просто "разговор закончен". */
    override fun endCall(identity: Identity) {
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
        endCallLocal(outcome)
    }

    /**
     * Вызов без ответа не должен висеть вечно: если звонящий пропал (приложение убито, вышел из
     * сети), у получателя рингтон иначе звонил бы бесконечно, а у звонящего "звонок" не кончался.
     */
    private fun scheduleRingTimeout(identity: Identity, callId: String) {
        scope.launch {
            delay(RING_TIMEOUT_MS)
            val s = _state.value
            if (s.callId != callId) return@launch
            when (s.phase) {
                CallPhase.OUTGOING_RINGING -> {
                    sendSignal(identity, s.peerPubKeyB64, CallSignalType.END, callId)
                    endCallLocal(CallOutcome.UNREACHABLE)
                }
                CallPhase.INCOMING_RINGING -> endCallLocal(CallOutcome.MISSED)
                else -> Unit
            }
        }
    }

    private fun sendSignal(identity: Identity, peerPubKeyB64: String, type: CallSignalType, callId: String, sdp: String? = null, ice: IceCandidate? = null) {
        val peer = peers().find { it.pubKeyB64 == peerPubKeyB64 } ?: run {
            Mb10Log.warnEvent(TAG, "call.signal_dropped_peer_unknown", "type" to type.name, "call" to callId.take(8), "peer" to Mb10Log.short(peerPubKeyB64))
            return
        }
        val signal = CallSignal(
            type = type, callId = callId, fromPubKeyB64 = identity.publicKeyB64, fromCallsign = identity.callsign,
            toPubKeyB64 = peerPubKeyB64, timestamp = System.currentTimeMillis(), sdp = sdp,
            iceSdpMid = ice?.sdpMid, iceSdpMLineIndex = ice?.sdpMLineIndex, iceCandidate = ice?.sdp
        )
        scope.launch {
            val ok = lines.sendLine(peer.host, peer.port, CallProtocol.encode(signal))
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

    private fun endCallLocal(outcome: String) {
        val s = _state.value
        Mb10Log.event(TAG, "call.ended", "call" to s.callId.take(8), "outcome" to outcome, "phase" to s.phase.name, "durationMs" to (System.currentTimeMillis() - s.startedAt))
        SoundPlayer.stopLoop()
        CallMedia.close()
        CallForegroundService.stop(app)
        _state.value = CallUiState()

        if (s.phase == CallPhase.IDLE) return // нечего логировать — звонка и не было
        val endedAt = System.currentTimeMillis()
        scope.launch {
            callLog.insert(
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
