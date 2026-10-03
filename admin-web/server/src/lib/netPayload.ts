import { createHash } from "node:crypto";
import { DAEMON_EFFECTS, moneyOrNull, SAFE_CODE, SAFE_ID } from "./itemInput.js";
import { tierLevel } from "./tier.js";

/**
 * Предметы для наполнения узла «Сети» в формате ItemPayloadCodec Моста (rules/ItemPayloadCodec.kt на ветке agent/netrun):
 *   SHARD|id|взлом 0/1|тир|b64(подсказка)|b64(заголовок)|b64(мета)|b64(текст)|деньги|расшифрован 0/1
 *   DAEMON|id|b64(имя)|коды через запятую|тир|ЭФФЕКТ
 * Текст — стандартный base64 с «=» (как у остальных форматов проекта). Формат уходит в подписанные карточки и менять его нельзя.
 */

const b64 = (text: string) => Buffer.from(text, "utf8").toString("base64");
const TIER_NAMES = new Set(["BASE", "HARD", "NIGHTMARE"]);

export interface StockPayload {
  kind: "SHARD" | "DAEMON";
  payload: string;
}

export type StockItemResult = { ok: true; item: StockPayload } | { ok: false; error: string };

/**
 * Идентификатор предмета внутри payload, если мастер не задал свой: от rid и номера — детерминированно, чтобы повтор запроса
 * с тем же rid дал те же байты (иначе Мост ответит rid_mismatch на «те же» параметры).
 */
const derivedId = (prefix: string, rid: string, index: number) => `${prefix}-${createHash("sha256").update(`${rid}|${index}`).digest("hex").slice(0, 8)}`;

const str = (v: unknown): string => (typeof v === "string" ? v : "");

/** Проверить ввод мастера и собрать payload предмета; те же правила, что у генератора QR в «Мастерской». */
export function buildStockItem(raw: unknown, rid: string, index: number): StockItemResult {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const where = `предмет ${index + 1}`;
  const tier = o.tier === undefined ? "BASE" : o.tier;
  if (typeof tier !== "string" || !TIER_NAMES.has(tier)) return { ok: false, error: `${where}: тир — BASE, HARD или NIGHTMARE` };
  if (o.type === "SHARD") {
    if (!str(o.title).trim() || !str(o.body).trim()) return { ok: false, error: `${where}: у шарда нужны заголовок и текст` };
    const money = moneyOrNull(o.moneyAmount);
    if (money === null) return { ok: false, error: `${where}: деньги — неотрицательное целое` };
    const id = o.id === undefined || o.id === "" ? derivedId("shard", rid, index) : o.id;
    if (typeof id !== "string" || !SAFE_ID.test(id)) return { ok: false, error: `${where}: id — латиница, цифры и _-. (до 64)` };
    const decryptAction = o.decryptAction === true;
    // Шард, требующий взлома, лежит в узле нерасшифрованным — игроку предстоит его вскрыть.
    const payload = ["SHARD", id, decryptAction ? "1" : "0", String(tierLevel(tier)), b64(str(o.valueHint)), b64(str(o.title)), b64(str(o.meta)), b64(str(o.body)), String(money), decryptAction ? "0" : "1"].join("|");
    return { ok: true, item: { kind: "SHARD", payload } };
  }
  if (o.type === "DAEMON") {
    const name = str(o.name).trim();
    const sequence = Array.isArray(o.sequence) ? o.sequence.filter((x): x is string => typeof x === "string") : [];
    if (!name || sequence.length === 0) return { ok: false, error: `${where}: у демона нужны имя и цепочка кодов` };
    if (!sequence.every((c) => SAFE_CODE.test(c))) return { ok: false, error: `${where}: коды демона — 1–8 латинских букв или цифр` };
    const effect = o.effect === undefined ? "EXTRACT_SHARD" : o.effect;
    if (typeof effect !== "string" || !DAEMON_EFFECTS.has(effect)) return { ok: false, error: `${where}: неизвестный эффект демона` };
    const id = o.id === undefined || o.id === "" ? derivedId("daemon", rid, index) : o.id;
    if (typeof id !== "string" || !SAFE_ID.test(id)) return { ok: false, error: `${where}: id — латиница, цифры и _-. (до 64)` };
    return { ok: true, item: { kind: "DAEMON", payload: ["DAEMON", id, b64(name), sequence.join(","), String(tierLevel(tier)), effect].join("|") } };
  }
  return { ok: false, error: `${where}: тип — SHARD или DAEMON` };
}
