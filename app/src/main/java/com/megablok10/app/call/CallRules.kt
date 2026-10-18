package com.megablok10.app.call

import com.megablok10.app.data.CallOutcome

/**
 * Чистые решения звонка (без WebRTC, Android и часов): какая фаза чем заканчивается, как реагировать на OFFER/ANSWER, что делать по
 * таймауту вызова и как меняется [CallUiState]. [CallManager] только исполняет выбранное (звук, медиа, сеть, журнал) — это то, что раньше
 * проверялось лишь e2e и на телефонах. Сигналы ([CallSignalType]) и версия протокола (`WireVersion.CALL`) здесь не меняются.
 */
object CallRules {
    /** Что игрок отправляет пиру, нажимая «положить трубку» на этой фазе, и как этот звонок запишется в журнал. */
    data class HangUp(val signal: CallSignalType, val outcome: String)

    /** Игрок отклонил входящий, отменил исходящий или завершил идущий: пиру уходит DECLINE (только на входящем) либо END. */
    fun hangUpByUser(phase: CallPhase): HangUp = when (phase) {
        CallPhase.INCOMING_RINGING -> HangUp(CallSignalType.DECLINE, CallOutcome.DECLINED)
        CallPhase.OUTGOING_RINGING -> HangUp(CallSignalType.END, CallOutcome.CANCELLED)
        CallPhase.IN_CALL, CallPhase.IDLE -> HangUp(CallSignalType.END, CallOutcome.COMPLETED)
    }

    /** Пир отклонил или завершил звонок — исход зависит от того, на какой фазе это застало нас. */
    fun outcomeOfPeerHangUp(phase: CallPhase): String = when (phase) {
        CallPhase.IN_CALL, CallPhase.IDLE -> CallOutcome.COMPLETED
        CallPhase.OUTGOING_RINGING -> CallOutcome.DECLINED
        CallPhase.INCOMING_RINGING -> CallOutcome.MISSED
    }

    /** Что делать, когда вызов звонил дольше положенного и не был принят. */
    sealed interface RingTimeout {
        /** Звонящему: сообщить пиру END и закончить [outcome] (пир не отвечает). */
        data class SendEndAndFinish(val outcome: String) : RingTimeout

        /** Получателю: звонок пропущен, пиру ничего не шлём. */
        data class Finish(val outcome: String) : RingTimeout

        /** Звонок уже идёт или закончен — таймаут вызова не при чём. */
        data object Ignore : RingTimeout
    }

    fun onRingTimeout(phase: CallPhase): RingTimeout = when (phase) {
        CallPhase.OUTGOING_RINGING -> RingTimeout.SendEndAndFinish(CallOutcome.UNREACHABLE)
        CallPhase.INCOMING_RINGING -> RingTimeout.Finish(CallOutcome.MISSED)
        CallPhase.IN_CALL, CallPhase.IDLE -> RingTimeout.Ignore
    }

    /** Реакция на пришедший OFFER. */
    enum class OfferAction {
        /** Повторный OFFER того же звонка от того же собеседника в идущем разговоре — перезапуск ICE: отвечаем ANSWER, звонок не трогаем. */
        RESTART_ICE,

        /** Уже заняты другим звонком — молча игнорируем (busy-сигнала в MVP нет). */
        IGNORE_BUSY,

        /** Свободны — это новый входящий звонок. */
        RING,
    }

    fun onOffer(current: CallUiState, signal: CallSignal): OfferAction = when {
        current.phase == CallPhase.IN_CALL && signal.callId == current.callId && signal.fromPubKeyB64 == current.peerPubKeyB64 -> OfferAction.RESTART_ICE
        current.phase != CallPhase.IDLE -> OfferAction.IGNORE_BUSY
        else -> OfferAction.RING
    }

    /** Реакция на пришедший ANSWER нашего звонка. */
    enum class AnswerAction {
        /** Звонок уже идёт — это ответ на наш перезапуск ICE: только применить SDP. */
        APPLY_RESTART_ANSWER,

        /** Первый ANSWER: собеседник принял, звонок переходит в разговор. */
        START_CALL,
    }

    fun onAnswer(current: CallUiState): AnswerAction =
        if (current.phase == CallPhase.IN_CALL) AnswerAction.APPLY_RESTART_ANSWER else AnswerAction.START_CALL

    /** Сигнал относится к текущему звонку (ANSWER, ICE, DECLINE, END чужого или давно закончившегося звонка игнорируются). */
    fun belongsToCurrentCall(current: CallUiState, signal: CallSignal): Boolean = current.callId == signal.callId

    /** Перезапускать ICE можно только в идущем разговоре того же звонка. */
    fun canRestartIce(current: CallUiState, callId: String): Boolean = current.callId == callId && current.phase == CallPhase.IN_CALL

    // ---- переходы состояния ----

    fun outgoing(callId: String, peerPubKeyB64: String, peerCallsign: String, now: Long): CallUiState =
        CallUiState(CallPhase.OUTGOING_RINGING, callId, peerPubKeyB64, peerCallsign, isOutgoing = true, startedAt = now)

    fun incoming(callId: String, peerPubKeyB64: String, peerCallsign: String, now: Long): CallUiState =
        CallUiState(CallPhase.INCOMING_RINGING, callId, peerPubKeyB64, peerCallsign, isOutgoing = false, startedAt = now)

    /** ICE соединился/потерял связь у звонка [callId]; чужой или закончившийся звонок состояние не меняет. */
    fun withConnected(current: CallUiState, callId: String, connected: Boolean): CallUiState =
        if (current.callId != callId) current else current.copy(audioConnected = connected, everConnected = current.everConnected || connected)

    /** Собеседник принял (мы звонили) или мы приняли сами: разговор начался в [now]. */
    fun inCall(current: CallUiState, now: Long): CallUiState = current.copy(phase = CallPhase.IN_CALL, phaseSince = now)

    /** Микрофон переключается только в разговоре и только на другое значение; иначе — null (ничего не менять). */
    fun withMuted(current: CallUiState, muted: Boolean): CallUiState? =
        if (current.phase != CallPhase.IN_CALL || current.muted == muted) null else current.copy(muted = muted)
}
