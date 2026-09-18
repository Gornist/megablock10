/** Зеркало enum class Tier в app/src/main/java/com/megablok10/app/breach/Tier.kt — держать в синхроне вручную. */
export const TIER_LEVEL: Record<string, number> = { BASE: 1, HARD: 2, NIGHTMARE: 3 };

export function tierLevel(tierName: string): number {
  return TIER_LEVEL[tierName] ?? 1;
}
