package com.megablok10.rules

/** Что решено про конкретный взлом — результат [SecAlertRules.decide], ещё без привязки к Context/БД. */
data class AlertPlan(val sendAt: Long, val revealCallsign: Boolean, val revealPreciseTime: Boolean)

/** Правила сигнала СБ (ревизия v9 §4) — чистая функция, общая для приложения и Моста. */
object SecAlertRules {
    /**
     * Именно тут решается, будет ли сигнал вообще, и что в нём раскроется.
     * null — сигнала не будет: свой узел (ownerFaction взломщика), FAIL на
     * тире BASE, либо BLACKOUT среди совпавших эффектов гасит его полностью.
     * TIMESKEW добавляет 10 минут к задержке; GHOST убирает позывной
     * взломщика из содержимого, даже если тир его обычно раскрывает.
     */
    fun decide(
        ownerFaction: String,
        intruderFaction: String,
        tier: Tier,
        outcome: BreachOutcome,
        matchedEffects: Set<DaemonEffect>,
        now: Long
    ): AlertPlan? {
        if (ownerFaction.isBlank() || ownerFaction == intruderFaction) return null
        if (outcome == BreachOutcome.FAIL && tier == Tier.BASE) return null
        if (DaemonEffect.BLACKOUT in matchedEffects) return null

        val baseDelayMs = if (tier == Tier.NIGHTMARE) 0L else 2 * 60_000L
        val timeskewBonus = if (DaemonEffect.TIMESKEW in matchedEffects) 10 * 60_000L else 0L
        return AlertPlan(
            sendAt = now + baseDelayMs + timeskewBonus,
            revealCallsign = tier != Tier.BASE && DaemonEffect.GHOST !in matchedEffects,
            revealPreciseTime = tier == Tier.NIGHTMARE
        )
    }
}
