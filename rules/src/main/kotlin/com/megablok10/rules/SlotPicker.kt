package com.megablok10.rules

/** Выбор слота контейнера для извлечения — чистая логика без БД; число уже принятых заявок на слот приходит снаружи. */
object SlotPicker {
    /**
     * Первый по порядку слот нужного типа, который extractorTier способен извлечь и который ещё не
     * исчерпан по тиражу (claimedCount — число уже принятых заявок на него).
     * excludeIndices — слоты, уже занятые ДРУГИМИ демонами в этой же попытке.
     */
    suspend fun pickSlot(
        container: Container,
        type: LootType,
        extractorTier: Tier,
        excludeIndices: Set<Int>,
        claimedCount: suspend (slotRef: String) -> Int
    ): Int? {
        for ((index, slot) in container.loot.withIndex()) {
            val fits = index !in excludeIndices && slot.type == type && extractorTier.covers(slot.tier)
            // Тираж спрашиваем, только если слот вообще подходит и конечен (0 — бесконечный): claimedCount ходит в базу.
            if (fits && (slot.copies <= 0 || claimedCount(container.slotRef(index)) < slot.copies)) return index
        }
        return null
    }
}
