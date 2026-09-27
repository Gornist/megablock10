import type { Db } from "../db/index.js";
import type { ContainerSlot } from "./containerSlots.js";
import { encodeContainerQr } from "./mb10QrCodec.js";
import { tierLevel } from "./tier.js";

export interface ContainerForQr {
  id: string;
  name: string;
  tier: string;
  ownerFaction: string | null;
  slots: ContainerSlot[];
}

/**
 * Каноническая строка QR контейнера — одна для «Показать QR» в Мастерской (routes/master.ts) и для электронного дисплея
 * (routes/displays.ts берёт контейнер из БД по id). Функция чистая и детерминированная: тот же контейнер — та же строка,
 * байт в байт, так что QR на бумаге и на дисплее один и тот же.
 */
export function containerQrString(c: ContainerForQr): string {
  return encodeContainerQr(
    c.id,
    c.name,
    tierLevel(c.tier),
    c.ownerFaction ?? "",
    c.slots.map((s) => ({ typeName: s.type, tierLevel: tierLevel(s.tier), copies: s.copies, payload: s.payload ?? "" })),
  );
}

export type ContainerQrLookup = { ok: true; qr: string; name: string } | { ok: false; status: 404 | 409; error: string };

/**
 * QR контейнера из справочника. Слот без зашифрованного содержимого (контейнер залит извне через POST /api/containers, а не создан
 * в Мастерской дашборда) переотрисовать нечем — такой QR был бы у телефона пустым, поэтому это ошибка, а не «QR без лута».
 */
export function containerQrFromDb(db: Db, id: string): ContainerQrLookup {
  const row = db.prepare(`SELECT id, name, tier, owner_faction, slots_json FROM containers WHERE id = ?`).get(id) as
    | { id: string; name: string; tier: string; owner_faction: string | null; slots_json: string }
    | undefined;
  if (!row) return { ok: false, status: 404, error: "unknown container" };
  const slots = JSON.parse(row.slots_json) as ContainerSlot[];
  if (slots.some((s) => typeof s.payload !== "string" || s.payload === "")) {
    return { ok: false, status: 409, error: "container slots have no payload (not created in the dashboard) — QR cannot be rebuilt" };
  }
  return { ok: true, name: row.name, qr: containerQrString({ id: row.id, name: row.name, tier: row.tier, ownerFaction: row.owner_faction, slots }) };
}
