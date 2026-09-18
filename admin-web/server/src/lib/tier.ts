/** Зеркало enum class Tier в app/src/main/java/com/megablok10/app/breach/Tier.kt — держать в синхроне вручную. */
export const TIER_LEVEL: Record<string, number> = { BASE: 1, HARD: 2, NIGHTMARE: 3 };

export function tierLevel(tierName: string): number {
  const level = TIER_LEVEL[tierName];
  if (level === undefined) {
    // Не бросаем и не меняем контракт (всегда есть число) — просто след в
    // логе, что где-то пришло имя тира вне {BASE,HARD,NIGHTMARE}, иначе это
    // тихо превращается в BASE и незаметно занижает сложность слота.
    console.warn(`[tier] неизвестное имя тира "${tierName}", откат к BASE (1)`);
    return 1;
  }
  return level;
}
