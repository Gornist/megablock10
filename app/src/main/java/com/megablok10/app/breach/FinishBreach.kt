package com.megablok10.app.breach

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.counterValue
import com.megablok10.app.identity.Identity
import com.megablok10.kit.sync.ChangeRecorder

/**
 * Сценарий «взлом завершён»: запись попытки для мастера (counters.breach), награда (эдди, шарды, демоны — [DaemonRewards]),
 * остывание узла, если что-то извлечено, и сигнал СБ фракции-владельцу ([SecAlertStore], решает сам — слать ли и когда).
 * Раньше это жило в корутине экрана взлома и обрывалось, если игрок успевал уйти с экрана; теперь его запускает ViewModel.
 */
class FinishBreach(
    private val changes: ChangeRecorder,
    private val applyRewards: suspend (me: Identity, container: Container, result: BreachResult, attemptId: String) -> RewardOutcome,
    private val markRewarded: suspend (containerId: String) -> Unit,
    private val raiseAlert: suspend (me: Identity, container: Container, outcome: BreachOutcome, matchedEffects: Set<DaemonEffect>) -> Unit,
) {
    /** [seed] — зерно сессии взлома: вместе с id контейнера даёт id попытки (идемпотентность наград при повторе). */
    suspend operator fun invoke(me: Identity, container: Container, result: BreachResult, seed: Long): RewardOutcome {
        val attemptId = "${container.id}:$seed"
        changes.record(
            ChangeField.COUNTERS_BREACH, null,
            counterValue("tier" to container.tier.name, "outcome" to result.outcome.name.lowercase()),
            ChangeReason.BREACH_ATTEMPT, sourceRef = attemptId, subjectKeyB64 = me.publicKeyB64,
        )
        val outcome = applyRewards(me, container, result, attemptId)
        if (result.matchedIds.isNotEmpty()) markRewarded(container.id)
        raiseAlert(me, container, result.outcome, outcome.matchedEffects)
        return outcome
    }
}
