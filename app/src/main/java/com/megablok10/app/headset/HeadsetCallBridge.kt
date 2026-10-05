package com.megablok10.app.headset

import com.megablok10.app.call.CallControls
import com.megablok10.app.call.CallPhase
import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Звонки для очков (срез 2 плана docs/netrun-phone-link.md): фаза звонка и журнал уходят очкам кадрами `call` и `call_log`, команды `accept`,
 * `decline`, `hangup`, `mute`, `start_call` исполняются через [CallControls]. Голос остаётся на телефоне (срез 3 — позже): очки управляют, не говорят.
 *
 * Команды проверяются по фазе звонка, как кнопки на экране телефона: принять и отклонить — только входящий, повесить — исходящий или идущий,
 * набрать — когда звонка нет и собеседник виден в сети. Без доступа к микрофону принять и набрать нельзя (разговор вышел бы односторонним);
 * разрешение игрок даёт при первом звонке на самом телефоне.
 */
class HeadsetCallBridge(
    private val calls: CallControls,
    private val onlinePlayers: () -> List<OnlinePlayer>,
    private val micGranted: () -> Boolean = { true },
) {
    /** Следит за звонком и журналом и шлёт кадры при каждом изменении (первое значение — сразу), пока жива [scope]. */
    fun observe(scope: CoroutineScope, send: (HeadsetOut) -> Boolean) {
        scope.launch { calls.state.map(::callFrame).distinctUntilChanged().collect { send(HeadsetOut.Call(it)) } }
        scope.launch { calls.observeLog().map(::callLogItems).distinctUntilChanged().collect { send(HeadsetOut.CallLog(it)) } }
    }

    /** Полное состояние по `resync`: текущий звонок и журнал. */
    suspend fun snapshot(send: (HeadsetOut) -> Boolean) {
        send(HeadsetOut.Call(callFrame(calls.state.value)))
        send(HeadsetOut.CallLog(callLogItems(calls.observeLog().first())))
    }

    /** Исполняет команду звонка. false — это не команда звонка (её разбирает зеркало переписки). */
    fun handle(identity: Identity, cmd: HeadsetCommand): Boolean {
        val phase = calls.state.value.phase
        when (cmd) {
            is HeadsetCommand.Accept -> if (phase == CallPhase.INCOMING_RINGING && micOk("accept")) calls.accept(identity)
            is HeadsetCommand.Decline -> if (phase == CallPhase.INCOMING_RINGING) calls.endCall(identity)
            is HeadsetCommand.Hangup -> if (phase == CallPhase.OUTGOING_RINGING || phase == CallPhase.IN_CALL) calls.endCall(identity)
            is HeadsetCommand.Mute -> calls.setMuted(cmd.on)
            is HeadsetCommand.StartCall -> if (phase == CallPhase.IDLE) startCall(identity, cmd.peer)
            else -> return false
        }
        return true
    }

    private fun startCall(identity: Identity, callsign: String) {
        val peer = onlinePlayers().firstOrNull { it.callsign == callsign }
        when {
            peer == null -> Mb10Log.warnEvent(TAG, "headset.call_peer_offline", "peer" to callsign)
            micOk("start_call") -> calls.startOutgoingCall(identity, peer)
        }
    }

    private fun micOk(command: String): Boolean {
        if (micGranted()) return true
        Mb10Log.warnEvent(TAG, "headset.call_no_mic", "command" to command)
        return false
    }

    private companion object {
        const val TAG = "Headset"
    }
}
