package com.megablok10.app.breach

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.counterValue
import com.megablok10.app.identity.Identity
import com.megablok10.kit.sync.ChangeRecorder

/** Почему взлом не начат (§2.2 ТЗ, BREACH_BLOCKED). Имя уходит мастеру в поле reason — не переименовывать. */
enum class BreachBlock { NO_LINK, COOLDOWN, EXHAUSTED }

/** Итог проверки перед взломом отсканированного контейнера. */
sealed interface BreachAccess {
    data object Open : BreachAccess
    /** [cooldownMinutes] — сколько ждать (для [BreachBlock.COOLDOWN], с округлением вверх, не меньше 1). */
    data class Blocked(val reason: BreachBlock, val cooldownMinutes: Long = 0) : BreachAccess
}

/**
 * Сценарий «можно ли взламывать этот контейнер» — до выбора демонов, чтобы попытку нельзя было потратить впустую или обойти правила:
 * 1) связь с сетью площадки (иначе сигнал СБ можно было бы обойти авиарежимом, ревизия v9 §5); 2) узел не остывает после
 * прошлой награды; 3) у узла остались неразобранные слоты. Каждый отказ уходит мастеру записью BREACH_BLOCKED.
 */
class CheckBreachAccess(
    private val isOnline: () -> Boolean,
    private val cooldownRemainingMs: suspend (containerId: String) -> Long,
    private val isExhausted: suspend (Container) -> Boolean,
    private val changes: ChangeRecorder,
) {
    suspend operator fun invoke(me: Identity, container: Container): BreachAccess {
        val blocked = when {
            !isOnline() -> BreachAccess.Blocked(BreachBlock.NO_LINK)
            else -> {
                val remainingMs = cooldownRemainingMs(container.id)
                when {
                    remainingMs > 0 -> BreachAccess.Blocked(BreachBlock.COOLDOWN, cooldownMinutes(remainingMs))
                    // Раньше это не проверялось вовсе — попытку можно было честно потратить на уже пустой контейнер и узнать об
                    // этом только в самом конце, через cacheExhausted в результате взлома.
                    isExhausted(container) -> BreachAccess.Blocked(BreachBlock.EXHAUSTED)
                    else -> null
                }
            }
        } ?: return BreachAccess.Open
        changes.record(
            ChangeField.COUNTERS_BLOCKED, null, counterValue("reason" to blocked.reason.name),
            ChangeReason.BREACH_BLOCKED, sourceRef = container.id, subjectKeyB64 = me.publicKeyB64,
        )
        return blocked
    }

    companion object {
        /** Минуты до конца остывания для игрока: с округлением вверх, «через 0 мин.» не бывает. */
        fun cooldownMinutes(remainingMs: Long): Long = (remainingMs / 60_000L + 1).coerceAtLeast(1)
    }
}
