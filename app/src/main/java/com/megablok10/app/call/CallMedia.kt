package com.megablok10.app.call

import android.content.Context
import com.megablok10.app.log.Mb10Log
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SoftwareVideoDecoderFactory
import org.webrtc.SoftwareVideoEncoderFactory
import org.webrtc.audio.JavaAudioDeviceModule

private const val TAG = "CallMedia"
private const val AUDIO_TRACK_ID = "mb10audio0"
private const val STREAM_ID = "mb10stream0"

/**
 * Вся работа с WebRTC — в одном месте, за простым callback-API, чтобы
 * CallManager не знал про PeerConnection/SdpObserver вообще. Только звук:
 * видео-кодеки (Software*, без EGL) заданы лишь потому, что Builder их
 * требует непустыми — реального видео-трека нигде не создаётся и не
 * добавляется. STUN/TURN не нужны — чистый LAN, ICE соберёт host-кандидаты
 * напрямую между парой устройств.
 */
object CallMedia {
    private var factory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var audioSource: AudioSource? = null
    private var localAudioTrack: AudioTrack? = null

    private var remoteDescriptionSet = false
    private val pendingRemoteCandidates = mutableListOf<IceCandidate>()

    private fun ensureFactory(context: Context): PeerConnectionFactory {
        factory?.let { return it }
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context.applicationContext).createInitializationOptions()
        )
        val adm = JavaAudioDeviceModule.builder(context.applicationContext).createAudioDeviceModule()
        // На живой проверке звонки, где звонящий — Xiaomi, не соединялись (ICE уходило в FAILED, тогда как в обратную сторону
        // работало): у ICE-кандидатов на этом телефоне без этой опции есть шанс уйти по мобильной сети или через VPN-интерфейс,
        // недоступный собеседнику на LAN, — тогда как сокеты чата и коллектора уже принудительно идут по Wi-Fi через WifiBinder.
        // STUN/TURN нет (чистый LAN, ADAPTER_TYPE_LOOPBACK тоже ни разу не пригодится паре реальных устройств).
        val options = PeerConnectionFactory.Options().apply {
            networkIgnoreMask = PeerConnectionFactory.Options.ADAPTER_TYPE_CELLULAR or
                PeerConnectionFactory.Options.ADAPTER_TYPE_VPN or
                PeerConnectionFactory.Options.ADAPTER_TYPE_LOOPBACK
        }
        val created = PeerConnectionFactory.builder()
            .setOptions(options)
            .setAudioDeviceModule(adm)
            .setVideoEncoderFactory(SoftwareVideoEncoderFactory())
            .setVideoDecoderFactory(SoftwareVideoDecoderFactory())
            .createPeerConnectionFactory()
        factory = created
        return created
    }

    /**
     * Поднимает голый PeerConnection без локального аудио-трека. Обработать
     * чужой SDP и начать сбор своих ICE-кандидатов можно и нужно сразу на
     * входящем OFFER, ещё до нажатия "Принять" — а вот доступ к микрофону
     * (addLocalAudioTrack) только после согласия игрока взять трубку, не раньше.
     */
    fun open(
        context: Context,
        onIceCandidate: (IceCandidate) -> Unit,
        onConnected: () -> Unit,
        onDisconnected: () -> Unit
    ) {
        close()
        val pcFactory = ensureFactory(context)

        val rtcConfig = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }
        val observer = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) = onIceCandidate(candidate)
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Mb10Log.event(TAG, "call.ice_state", "state" to state.name)
                when (state) {
                    PeerConnection.IceConnectionState.CONNECTED,
                    PeerConnection.IceConnectionState.COMPLETED -> onConnected()
                    PeerConnection.IceConnectionState.FAILED,
                    PeerConnection.IceConnectionState.DISCONNECTED,
                    PeerConnection.IceConnectionState.CLOSED -> onDisconnected()
                    else -> {}
                }
            }
            override fun onSignalingChange(state: PeerConnection.SignalingState) { Mb10Log.event(TAG, "call.signaling_state", "state" to state.name) }
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) { Mb10Log.event(TAG, "call.ice_gathering", "state" to state.name) }
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
            override fun onAddStream(stream: MediaStream) {}
            override fun onRemoveStream(stream: MediaStream) {}
            override fun onDataChannel(channel: DataChannel) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
        }
        val pc = pcFactory.createPeerConnection(rtcConfig, observer) ?: run {
            Mb10Log.w(TAG, "createPeerConnection вернул null")
            return
        }
        peerConnection = pc
    }

    /** Отдельно от open() — вызывается только в момент, когда игрок реально согласился на звонок (исходящий сразу, входящий — по "Принять"). */
    fun addLocalAudioTrack(context: Context) {
        val pc = peerConnection ?: return
        if (localAudioTrack != null) return
        val pcFactory = ensureFactory(context)
        val source = pcFactory.createAudioSource(MediaConstraints())
        audioSource = source
        val track = pcFactory.createAudioTrack(AUDIO_TRACK_ID, source)
        localAudioTrack = track
        pc.addTrack(track, listOf(STREAM_ID))
    }

    fun createOffer(onReady: (String) -> Unit) {
        val pc = peerConnection ?: return
        pc.createOffer(sdpObserver(onCreate = { sdp ->
            pc.setLocalDescription(sdpObserver(onSet = { onReady(sdp.description) }), sdp)
        }), MediaConstraints())
    }

    fun createAnswer(onReady: (String) -> Unit) {
        val pc = peerConnection ?: return
        pc.createAnswer(sdpObserver(onCreate = { sdp ->
            pc.setLocalDescription(sdpObserver(onSet = { onReady(sdp.description) }), sdp)
        }), MediaConstraints())
    }

    fun setRemoteOffer(sdp: String) = setRemoteDescription(SessionDescription(SessionDescription.Type.OFFER, sdp))

    fun setRemoteAnswer(sdp: String) = setRemoteDescription(SessionDescription(SessionDescription.Type.ANSWER, sdp))

    private fun setRemoteDescription(description: SessionDescription) {
        val pc = peerConnection ?: return
        pc.setRemoteDescription(sdpObserver(onSet = {
            remoteDescriptionSet = true
            pendingRemoteCandidates.forEach { pc.addIceCandidate(it) }
            pendingRemoteCandidates.clear()
        }), description)
    }

    /** ICE трещит независимо от статуса ответа — кандидаты, пришедшие раньше setRemoteDescription, просто копятся и применяются потом. */
    fun addRemoteIceCandidate(sdpMid: String, sdpMLineIndex: Int, candidate: String) {
        val ice = IceCandidate(sdpMid, sdpMLineIndex, candidate)
        val pc = peerConnection
        if (pc == null || !remoteDescriptionSet) {
            pendingRemoteCandidates.add(ice)
        } else {
            pc.addIceCandidate(ice)
        }
    }

    fun close() {
        peerConnection?.close()
        peerConnection?.dispose()
        peerConnection = null
        audioSource?.dispose()
        audioSource = null
        localAudioTrack = null
        remoteDescriptionSet = false
        pendingRemoteCandidates.clear()
    }

    private fun sdpObserver(
        onCreate: (SessionDescription) -> Unit = {},
        onSet: () -> Unit = {},
        onCreateFailure: (String) -> Unit = { Mb10Log.w(TAG, "createOffer/Answer failed: $it") },
        onSetFailure: (String) -> Unit = { Mb10Log.w(TAG, "setLocal/RemoteDescription failed: $it") }
    ) = object : SdpObserver {
        override fun onCreateSuccess(sdp: SessionDescription) = onCreate(sdp)
        override fun onSetSuccess() = onSet()
        override fun onCreateFailure(error: String) = onCreateFailure.invoke(error)
        override fun onSetFailure(error: String) = onSetFailure.invoke(error)
    }
}
