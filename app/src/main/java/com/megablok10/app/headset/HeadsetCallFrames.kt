package com.megablok10.app.headset

import com.megablok10.app.call.CallPhase
import com.megablok10.app.call.CallUiState
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome

/** Сколько записей журнала звонков показывать в очках. */
const val HEADSET_CALL_LOG_DEPTH = 20

private const val MS_PER_S = 1000L

/** Текущий звонок для очков: фаза как у [CallPhase], `since_ts` — когда началась эта фаза (ответили — начало разговора), unix-секунды. */
fun callFrame(state: CallUiState): HeadsetCall = HeadsetCall(
    phase = when (state.phase) {
        CallPhase.IDLE -> HeadsetCall.IDLE
        CallPhase.OUTGOING_RINGING -> HeadsetCall.OUTGOING
        CallPhase.INCOMING_RINGING -> HeadsetCall.INCOMING
        CallPhase.IN_CALL -> HeadsetCall.IN_CALL
    },
    peer = state.peerCallsign,
    sinceTs = if (state.phase == CallPhase.IDLE) 0L else state.phaseSince / MS_PER_S,
    muted = state.muted,
)

/**
 * Журнал звонков для очков (новые сверху, как отдаёт Room): `in` — входящий, `out` — исходящий, `missed` — пропущенный входящий;
 * длительность — только у звонков, которые шли (состоялся или оборвался).
 */
fun callLogItems(log: List<CallLogEntity>): List<HeadsetCallLogItem> = log.take(HEADSET_CALL_LOG_DEPTH).map { e ->
    val dir = when {
        e.outcome == CallOutcome.MISSED -> HeadsetCallLogItem.MISSED
        e.direction == CallDirection.OUTGOING -> HeadsetCallLogItem.OUT
        else -> HeadsetCallLogItem.IN
    }
    val talked = e.outcome == CallOutcome.COMPLETED || e.outcome == CallOutcome.LOST
    HeadsetCallLogItem(
        peer = e.peerCallsign,
        dir = dir,
        ts = e.startedAt / MS_PER_S,
        durationS = if (talked) ((e.endedAt - e.startedAt) / MS_PER_S).coerceAtLeast(0L) else 0L,
    )
}
