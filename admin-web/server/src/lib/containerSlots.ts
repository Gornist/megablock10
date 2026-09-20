export interface ContainerSlot {
  index: number;
  type: "SHARD" | "DAEMON";
  tier: string;
  copies: number;
  title: string;
  /** Зашифрованный LootCodec-блок (см. lib/lootCrypto.ts) — есть только у слотов, сгенерированных прямо в дашборде (§ Мастерская), нужен для переотрисовки QR. У импортированных извне контейнеров может отсутствовать. */
  payload?: string;
}

const SLOT_TYPES = new Set(["SHARD", "DAEMON"]);

interface RawSlotFields {
  type?: unknown;
  tier?: unknown;
  copies?: unknown;
  title?: unknown;
  payload?: unknown;
}

export type SlotValidationResult = { ok: true; slot: ContainerSlot } | { ok: false; error: string };

/**
 * Единственное место, проверяющее поля готового ContainerSlot (index/type/
 * tier/copies/title/payload) перед тем, как он попадёт в slots_json —
 * раньше это делал только routes/master.ts построчно внутри своего
 * генератора QR, а routes/containers.ts (заливка справочника из Мастерской/
 * импорта) писала присланный массив как есть, без проверки. Теперь оба
 * роута вызывают эту функцию перед upsertContainer(), так что безопасность
 * одна и та же независимо от того, откуда пришли слоты.
 */
export function validateContainerSlot(index: number, raw: RawSlotFields): SlotValidationResult {
  if (typeof raw.type !== "string" || !SLOT_TYPES.has(raw.type)) {
    return { ok: false, error: `slot ${index}: type must be SHARD or DAEMON` };
  }
  if (typeof raw.tier !== "string" || !raw.tier.trim()) {
    return { ok: false, error: `slot ${index}: tier must be a non-empty string` };
  }
  if (!Number.isInteger(raw.copies) || (raw.copies as number) < 0) {
    return { ok: false, error: `slot ${index}: copies must be a non-negative integer` };
  }
  if (typeof raw.title !== "string") {
    return { ok: false, error: `slot ${index}: title must be a string` };
  }
  if (raw.payload !== undefined && typeof raw.payload !== "string") {
    return { ok: false, error: `slot ${index}: payload must be a string` };
  }

  return {
    ok: true,
    slot: {
      index,
      type: raw.type as "SHARD" | "DAEMON",
      tier: raw.tier,
      copies: raw.copies as number,
      title: raw.title,
      payload: raw.payload as string | undefined,
    },
  };
}

/** Тот же валидатор, но сразу по всему массиву "сырых" слотов (routes/containers.ts) — index берётся из позиции в массиве, если не задан явно. */
export function validateContainerSlots(raw: unknown): { ok: true; slots: ContainerSlot[] } | { ok: false; error: string } {
  if (!Array.isArray(raw)) return { ok: false, error: "slots must be an array" };

  const slots: ContainerSlot[] = [];
  for (const [i, item] of raw.entries()) {
    const s = (item ?? {}) as RawSlotFields & { index?: unknown };
    const index = Number.isInteger(s.index) ? (s.index as number) : i;
    const result = validateContainerSlot(index, s);
    if (!result.ok) return result;
    slots.push(result.slot);
  }
  return { ok: true, slots };
}
