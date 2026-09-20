import { randomUUID } from "node:crypto";
import type { Db } from "../db/index.js";
import type { Field } from "./changeRecord.js";
import { RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX } from "./identityDefaults.js";
import type { PlayerBase } from "./playerSummary.js";
import type { CharacterSnapshot } from "./projection.js";

/** Только скалярные поля персонажа — правка daemons.add/shards.add/counters.* через дашборд не предусмотрена (нет формы, нет смысла: это коллекции, не значения). */
export const OVERRIDABLE_FIELDS: Field[] = ["balance", "ramCapacity", "callsign", "faction"];
/** Массово правим только то, что не должно быть уникальным: позывной у каждого свой. */
export const BULK_FIELDS: Field[] = ["balance", "ramCapacity", "faction"];

export type OverrideMode = "set" | "add";

/**
 * Значение должно быть таким, которое телефон реально применит: иначе на
 * дашборде оно отображается (NaN, пустой позывной), а устройство молча его
 * игнорирует — расхождение навсегда.
 */
export function validateValue(field: Field, value: string): string | null {
  if (field === "balance" && !/^-?\d+$/.test(value)) return "balance must be an integer";
  if (field === "ramCapacity" && !(/^\d+$/.test(value) && Number(value) >= RAM_CAPACITY_DEFAULT && Number(value) <= RAM_CAPACITY_MAX)) {
    return `ramCapacity must be an integer from ${RAM_CAPACITY_DEFAULT} to ${RAM_CAPACITY_MAX}`;
  }
  if ((field === "callsign" || field === "faction") && value.trim() === "") return `${field} must not be empty`;
  return null;
}

export function currentFieldValue(snapshot: Pick<CharacterSnapshot, "balance" | "ramCapacity" | "callsign" | "faction"> | null, field: Field): string | null {
  if (!snapshot) return null;
  switch (field) {
    case "balance":
      return String(snapshot.balance);
    case "ramCapacity":
      return String(snapshot.ramCapacity);
    case "callsign":
      return snapshot.callsign;
    case "faction":
      return snapshot.faction;
    default:
      return null;
  }
}

/**
 * Итоговое значение поля с учётом режима. "set" — как есть; "add" — дельта к
 * текущему (только числовые поля; RAM зажимается в допустимый диапазон, чтобы
 * «+3 всем» не выводил игрока за потолок деки).
 */
export function resolveValue(
  field: Field,
  mode: OverrideMode,
  raw: string,
  snapshot: Pick<CharacterSnapshot, "balance" | "ramCapacity"> | null,
): { ok: true; value: string } | { ok: false; error: string } {
  if (mode === "set") {
    const error = validateValue(field, raw);
    return error ? { ok: false, error } : { ok: true, value: raw };
  }
  if (field !== "balance" && field !== "ramCapacity") return { ok: false, error: "mode add is only for balance and ramCapacity" };
  // «+200» — естественная запись прибавки, Number("+200") тоже даёт 200, но регэксп её не пропускал.
  const cleaned = raw.trim().replace(/^\+/, "");
  if (!/^-?\d+$/.test(cleaned)) return { ok: false, error: "delta must be an integer" };
  const delta = Number(cleaned);
  if (field === "balance") {
    const next = (snapshot?.balance ?? 0) + delta;
    if (!Number.isSafeInteger(next)) return { ok: false, error: "balance overflow" };
    return { ok: true, value: String(next) };
  }
  const next = Math.min(RAM_CAPACITY_MAX, Math.max(RAM_CAPACITY_DEFAULT, (snapshot?.ramCapacity ?? RAM_CAPACITY_DEFAULT) + delta));
  return { ok: true, value: String(next) };
}

export interface TargetSelector {
  keys?: unknown;
  faction?: unknown;
  all?: unknown;
}

export type TargetResult = { ok: true; players: PlayerBase[]; label: string } | { ok: false; error: string };

const MAX_KEYS = 500;

/** Ровно один способ выбрать адресатов: список ключей, фракция целиком или все игроки. */
export function selectTargets(base: PlayerBase[], sel: TargetSelector): TargetResult {
  const given = [sel.keys !== undefined, sel.faction !== undefined, sel.all === true].filter(Boolean).length;
  if (given !== 1) return { ok: false, error: "specify exactly one of keys, faction, all" };

  if (sel.keys !== undefined) {
    if (!Array.isArray(sel.keys) || sel.keys.length === 0 || sel.keys.length > MAX_KEYS || !sel.keys.every((k) => typeof k === "string")) {
      return { ok: false, error: `keys must be a non-empty array of strings (max ${MAX_KEYS})` };
    }
    const wanted = new Set(sel.keys as string[]);
    return { ok: true, players: base.filter((p) => wanted.has(p.publicKeyB64)), label: `выбранные игроки (${wanted.size})` };
  }
  if (sel.faction !== undefined) {
    if (typeof sel.faction !== "string") return { ok: false, error: "faction must be a string" };
    const faction = sel.faction;
    return { ok: true, players: base.filter((p) => p.faction === faction), label: `фракция «${faction || "без фракции"}»` };
  }
  return { ok: true, players: base, label: "все игроки" };
}

export interface MasterRecordSpec {
  subjectKey: string;
  field: string;
  oldValue: string | null;
  newValue: string;
  sourceRef: string;
}

/**
 * Записывает мастерские правки в changes и ставит их в очередь доставки на
 * устройства — ОДНОЙ транзакцией на весь набор: либо все и в очередь, либо
 * ничего (иначе возможна правка, видная в истории на дашборде, но так и не
 * долетевшая до игрока, если процесс упадёт между двумя INSERT).
 *
 * seq мастерских правок — ОТДЕЛЬНЫЙ отрицательный диапазон, не "следующий
 * после устройства". Устройство нумерует seq САМО и независимо от сервера
 * (offline-first), а UNIQUE(subject_key, seq) не позволил бы лечь обоим:
 * законная запись игрока получила бы "seq already used" и потерялась бы
 * молча. Отрицательные числа устройство не выдаёт никогда (его счётчик
 * стартует с 1) — коллизия структурно невозможна. Порядок применения берётся
 * не из seq (см. projection.ts), а из received_at.
 */
export function insertMasterRecords(db: Db, masterId: string, specs: MasterRecordSpec[]): { id: string; subjectKey: string; seq: number }[] {
  const minSeqStmt = db.prepare(`SELECT MIN(seq) AS minSeq FROM changes WHERE subject_key = ?`);
  const insertChange = db.prepare(
    `INSERT INTO changes (id, subject_key, seq, happened_at, received_at, field, old_value, new_value, reason, source_ref, actor, signature)
     VALUES (@id, @subject_key, @seq, @happened_at, @received_at, @field, @old_value, @new_value, 'MASTER_OVERRIDE', @source_ref, @actor, '')`,
  );
  const insertPending = db.prepare(`INSERT INTO master_pending (change_id, subject_key, delivered, created_at) VALUES (?, ?, 0, ?)`);

  const run = db.transaction(() => {
    const now = Date.now();
    return specs.map((spec) => {
      const id = randomUUID();
      const minSeq = (minSeqStmt.get(spec.subjectKey) as { minSeq: number | null }).minSeq;
      const seq = Math.min(0, minSeq ?? 0) - 1;
      insertChange.run({
        id,
        subject_key: spec.subjectKey,
        seq,
        happened_at: now,
        received_at: now,
        field: spec.field,
        old_value: spec.oldValue,
        new_value: spec.newValue,
        source_ref: spec.sourceRef,
        actor: `master:${masterId}`,
      });
      insertPending.run(id, spec.subjectKey, now);
      return { id, subjectKey: spec.subjectKey, seq };
    });
  });
  return run();
}
