import type { Db } from "../db/index.js";
import { cachedByDbVersion } from "./dbCache.js";

/**
 * Проверки целостности: коллектор принимает баланс из записей устройств как
 * есть, а подпись гарантирует лишь авторство, не правдивость. Здесь — дешёвые
 * перекрёстные проверки по уже собранным записям, без изменения протокола.
 * Всё, что не зависит от «сейчас», считается один раз на версию БД
 * (см. dbCache.ts); окна по времени применяет вызывающий код.
 */

/** Причины, которыми баланс законно растёт: награды, получение перевода, возврат отменённого, старт/сброс, правка мастера. */
const BALANCE_GAIN_REASONS = new Set([
  "BREACH_EDDIES",
  "BREACH_LOOT",
  "SHARD_SCAN",
  "TRANSFER_IN",
  "TRANSFER_CANCELLED",
  "MASTER_OVERRIDE",
  "CHARACTER_CREATED",
  "CHARACTER_RESET",
]);

export interface ChainBreak {
  subjectKey: string;
  /** Время получения записи, на которой цепочка порвалась (часы сервера). */
  at: number;
  expected: number;
  actual: number;
  /** Сколько разрывов у этого игрока всего. */
  count: number;
}

export interface DuplicateReceive {
  sourceRef: string;
  reason: "TRANSFER_IN" | "ITEM_TRANSFER_IN";
  subjectKeys: string[];
  at: number;
}

export interface UnpairedTransfer {
  txId: string;
  kind: "money" | "item";
  /** Какая половина есть: «out» — отправка без получения (и без отмены), «in» — получение без отправки. */
  side: "out" | "in";
  subjectKey: string;
  at: number;
  /** Сумма для денежных переводов (по дельте баланса), иначе null. */
  amount: number | null;
}

export interface IntegrityFindings {
  chainBreaks: ChainBreak[];
  duplicateReceives: DuplicateReceive[];
  unpairedTransfers: UnpairedTransfer[];
}

interface BalanceRow {
  subject_key: string;
  seq: number;
  received_at: number;
  old_value: string | null;
  new_value: string | null;
}

/**
 * Цепочка oldValue → newValue: у каждой записи баланса oldValue должен равняться newValue
 * предыдущей записи того же устройства (по seq). Значения, выставленные мастером,
 * исключение: телефон мог применить правку между двумя записями.
 */
function findChainBreaks(db: Db): ChainBreak[] {
  const rows = db
    .prepare(`SELECT subject_key, seq, received_at, old_value, new_value FROM changes WHERE field = 'balance' ORDER BY subject_key, seq`)
    .all() as BalanceRow[];

  const out: ChainBreak[] = [];
  let i = 0;
  while (i < rows.length) {
    let j = i;
    while (j < rows.length && rows[j].subject_key === rows[i].subject_key) j++;
    const group = rows.slice(i, j);
    i = j;

    // Мастерские записи — с отрицательным seq (см. masterRecords.ts), в цепочку устройства не входят.
    const masterValues = new Set(group.filter((r) => r.seq < 0).map((r) => Number(r.new_value)));
    let prev: BalanceRow | null = null;
    let last: ChainBreak | null = null;
    let count = 0;
    for (const r of group) {
      if (r.seq < 0) continue;
      if (prev && r.old_value !== null) {
        const expected = Number(prev.new_value);
        const actual = Number(r.old_value);
        if (Number.isFinite(expected) && Number.isFinite(actual) && expected !== actual && !masterValues.has(actual)) {
          count++;
          last = { subjectKey: r.subject_key, at: r.received_at, expected, actual, count };
        }
      }
      prev = r;
    }
    if (last) out.push({ ...last, count });
  }
  return out;
}

/**
 * Один и тот же source_ref получения у двух разных игроков: честное приложение
 * (карточки v2 адресованы конкретному получателю) так не делает, значит это
 * модифицированный клиент или повторно проигранная карточка.
 */
function findDuplicateReceives(db: Db): DuplicateReceive[] {
  const rows = db
    .prepare(
      `SELECT source_ref, reason, GROUP_CONCAT(DISTINCT subject_key) AS keys, MAX(received_at) AS at
       FROM changes WHERE reason IN ('TRANSFER_IN', 'ITEM_TRANSFER_IN') AND source_ref IS NOT NULL
       GROUP BY source_ref, reason HAVING COUNT(DISTINCT subject_key) > 1`,
    )
    .all() as { source_ref: string; reason: DuplicateReceive["reason"]; keys: string; at: number }[];
  return rows.map((r) => ({ sourceRef: r.source_ref, reason: r.reason, subjectKeys: r.keys.split(","), at: r.at }));
}

/** Отправка без получения/отмены и получение без отправки. Сколько это уже висит — решает вызывающий по `at`. */
function findUnpairedTransfers(db: Db): UnpairedTransfer[] {
  type Row = { subject_key: string; source_ref: string; reason: string; received_at: number; old_value: string | null; new_value: string | null };
  const rows = db
    .prepare(
      `SELECT subject_key, source_ref, reason, received_at, old_value, new_value FROM changes
       WHERE source_ref IS NOT NULL AND reason IN
         ('TRANSFER_OUT', 'TRANSFER_IN', 'TRANSFER_CANCELLED', 'ITEM_TRANSFER_OUT', 'ITEM_TRANSFER_IN', 'ITEM_TRANSFER_CANCELLED')`,
    )
    .all() as Row[];

  const byRef = new Map<string, Row[]>();
  for (const r of rows) {
    const list = byRef.get(r.source_ref) ?? [];
    list.push(r);
    byRef.set(r.source_ref, list);
  }

  const out: UnpairedTransfer[] = [];
  for (const [txId, list] of byRef) {
    for (const kind of ["money", "item"] as const) {
      const prefix = kind === "money" ? "TRANSFER_" : "ITEM_TRANSFER_";
      const outRow = list.find((r) => r.reason === `${prefix}OUT`);
      const inRow = list.find((r) => r.reason === `${prefix}IN`);
      const cancelled = list.some((r) => r.reason === `${prefix}CANCELLED`);
      if (outRow && !inRow && !cancelled) {
        out.push({ txId, kind, side: "out", subjectKey: outRow.subject_key, at: outRow.received_at, amount: kind === "money" ? Number(outRow.old_value ?? 0) - Number(outRow.new_value ?? 0) : null });
      } else if (inRow && !outRow) {
        out.push({ txId, kind, side: "in", subjectKey: inRow.subject_key, at: inRow.received_at, amount: kind === "money" ? Number(inRow.new_value ?? 0) - Number(inRow.old_value ?? 0) : null });
      }
    }
  }
  return out;
}

const caches = new WeakMap<Db, () => IntegrityFindings>();

export function getIntegrityFindings(db: Db): IntegrityFindings {
  let cached = caches.get(db);
  if (!cached) {
    cached = cachedByDbVersion(db, () => ({
      chainBreaks: findChainBreaks(db),
      duplicateReceives: findDuplicateReceives(db),
      unpairedTransfers: findUnpairedTransfers(db),
    }));
    caches.set(db, cached);
  }
  return cached();
}

export interface UnexplainedJump {
  id: string;
  subjectKey: string;
  at: number;
  delta: number;
  reason: string;
}

/** Крупный рост баланса по причине, которая денег не выдаёт (например RAM_UPGRADE или TRANSFER_OUT): так выглядит подделка. Только записи новее since. */
export function findUnexplainedJumps(db: Db, since: number, minDelta: number): UnexplainedJump[] {
  const rows = db
    .prepare(`SELECT id, subject_key, received_at, reason, old_value, new_value FROM changes WHERE field = 'balance' AND received_at > ?`)
    .all(since) as { id: string; subject_key: string; received_at: number; reason: string; old_value: string | null; new_value: string | null }[];
  const out: UnexplainedJump[] = [];
  for (const r of rows) {
    if (BALANCE_GAIN_REASONS.has(r.reason)) continue;
    const delta = Number(r.new_value ?? 0) - Number(r.old_value ?? 0);
    if (delta >= minDelta) out.push({ id: r.id, subjectKey: r.subject_key, at: r.received_at, delta, reason: r.reason });
  }
  return out;
}
