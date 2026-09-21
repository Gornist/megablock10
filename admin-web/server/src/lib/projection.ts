import type { Db } from "../db/index.js";
import type { Field, StoredChangeRow } from "./changeRecord.js";
import { RAM_CAPACITY_DEFAULT } from "./identityDefaults.js";
import { parseSafe } from "./json.js";

import type { CharacterSnapshot, Counters, DaemonEntry, ShardEntry } from "../apiTypes.js";

export type { CharacterSnapshot };

/** Поля записи, которые читает свёртка (подмножество StoredChangeRow). */
export type ProjectionRow = Pick<StoredChangeRow, "subject_key" | "field" | "new_value" | "reason" | "received_at" | "seq">;

const SCALAR_FIELDS: Field[] = ["balance", "ramCapacity", "callsign", "faction"];

function emptyCounters(): Counters {
  return { breaches: {}, slotsClaimed: 0, alertsSent: 0, alertsSuppressed: 0, breachesBlocked: {} };
}

/** Только то, что читает свёртка: подписи, actor, source_ref и т.п. ей не нужны, а на десятках тысяч строк их материализация заметна. */
const PROJECTION_COLUMNS = "subject_key, field, new_value, reason, received_at, seq";

/**
 * Записи для свёртки в порядке применения (игрок, received_at, seq). received_at, не seq — seq осмысленно сравним только внутри
 * одного устройства, а мастерские правки живут в отдельном (отрицательном) диапазоне; received_at общий для всех источников и
 * отражает реальный порядок поступления на сервер — то, что нужно для «последняя правка выигрывает» (§6.4 ТЗ).
 * until — состояние «на момент T» по часам сервера: ровно то, что видел бы дашборд в тот момент. key — только один игрок.
 */
function selectRows(db: Db, until?: number, key?: string): Iterable<ProjectionRow> {
  const clauses: string[] = [];
  const params: unknown[] = [];
  if (key !== undefined) {
    clauses.push("subject_key = ?");
    params.push(key);
  }
  if (until !== undefined) {
    clauses.push("received_at <= ?");
    params.push(until);
  }
  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  return db.prepare(`SELECT ${PROJECTION_COLUMNS} FROM changes ${where} ORDER BY subject_key, received_at ASC, seq ASC`).iterate(...params) as Iterable<ProjectionRow>;
}

/** slotsClaimed — не из changes, а из реестра арбитража (§5 ТЗ): именно slot_claims фиксирует, кто реально получил тиражный слот через сервер. */
function claimCounts(db: Db, until?: number, key?: string): Map<string, number> {
  const clauses = ["revoked = 0"];
  const params: unknown[] = [];
  if (key !== undefined) {
    clauses.push("claimant_key = ?");
    params.push(key);
  }
  if (until !== undefined) {
    clauses.push("claimed_at <= ?");
    params.push(until);
  }
  const rows = db.prepare(`SELECT claimant_key, COUNT(*) AS n FROM slot_claims WHERE ${clauses.join(" AND ")} GROUP BY claimant_key`).all(...params) as { claimant_key: string; n: number }[];
  return new Map(rows.map((r) => [r.claimant_key, r.n]));
}

/**
 * Снимок персонажа, посчитанный SQL-выборкой по changes на каждое чтение — никакой отдельной таблицы-снимка нет и поддерживать её в
 * синхроне не нужно. Для ~100 игроков и десятков тысяч записей это дешевле, чем инкрементальное обновление, и не может разойтись
 * с историей по определению — история и есть источник истины.
 *
 * Формат JSON внутри old_value/new_value для полей daemons, shards, counters — рабочий черновик протокола, зафиксированный вместе
 * с Android-клиентом: daemons.add/shards.add несут полный объект сущности, .remove/.decrypt несут { daemonId | shardId }, counters.* — { path, delta }.
 */
export function projectCharacter(db: Db, subjectKeyB64: string, until?: number): CharacterSnapshot | null {
  return projectRows(subjectKeyB64, [...selectRows(db, until, subjectKeyB64)], claimCounts(db, until, subjectKeyB64).get(subjectKeyB64) ?? 0);
}

/**
 * Снимки ВСЕХ персонажей за один проход по истории: одна выборка, упорядоченная по (игрок, время), вместо запроса на каждого игрока.
 * Тот же projectRows, что и у projectCharacter, поэтому результат для каждого ключа одинаков (это проверяется тестом).
 */
export function projectAll(db: Db, until?: number): CharacterSnapshot[] {
  const claims = claimCounts(db, until);
  const out: CharacterSnapshot[] = [];
  let key: string | null = null;
  let group: ProjectionRow[] = [];
  const flush = () => {
    if (key === null) return;
    const snapshot = projectRows(key, group, claims.get(key) ?? 0);
    if (snapshot) out.push(snapshot);
  };
  for (const row of selectRows(db, until)) {
    if (row.subject_key !== key) {
      flush();
      key = row.subject_key;
      group = [];
    }
    group.push(row);
  }
  flush();
  return out;
}

/** Свёртка уже упорядоченных (received_at, seq) записей одного игрока в снимок. null — записей нет. */
function projectRows(subjectKeyB64: string, rows: ProjectionRow[], slotsClaimed: number): CharacterSnapshot | null {
  if (rows.length === 0) return null;

  const snapshot: CharacterSnapshot = {
    publicKeyB64: subjectKeyB64,
    callsign: "",
    faction: "",
    ramCapacity: RAM_CAPACITY_DEFAULT,
    balance: 0,
    daemons: [],
    shards: [],
    counters: emptyCounters(),
    lastSeenAt: 0,
    lastSeq: 0,
    sessionResetAt: null,
  };

  const daemons = new Map<string, DaemonEntry>();
  const shards = new Map<string, ShardEntry>();

  for (const row of rows) {
    applyRow(snapshot, daemons, shards, row);
    // Мастерская правка/объявление — действие мастера, а не признак того, что игрок на связи.
    if (row.reason !== "MASTER_OVERRIDE") snapshot.lastSeenAt = Math.max(snapshot.lastSeenAt, row.received_at);
    snapshot.lastSeq = Math.max(snapshot.lastSeq, row.seq);
  }

  snapshot.daemons = [...daemons.values()];
  snapshot.shards = [...shards.values()];
  snapshot.counters.slotsClaimed = slotsClaimed;
  return snapshot;
}

function applyRow(
  snapshot: CharacterSnapshot,
  daemons: Map<string, DaemonEntry>,
  shards: Map<string, ShardEntry>,
  row: ProjectionRow,
) {
  const field = row.field as Field;

  // Сброс сессии стирает данные на УСТРОЙСТВЕ, а персонаж остаётся у мастера для повторной выдачи: значения в снимке не трогаем,
  // только помечаем «сессия сброшена» (последние позывной и фракция лежат в old_value этих записей — они и так уже в снимке).
  if (row.reason === "CHARACTER_RESET") {
    snapshot.sessionResetAt = Math.max(snapshot.sessionResetAt ?? 0, row.received_at);
    return;
  }

  if (SCALAR_FIELDS.includes(field)) {
    applyScalar(snapshot, field, row.new_value);
    return;
  }

  switch (field) {
    case "daemons.add": {
      const d = parseSafe<DaemonEntry>(row.new_value);
      if (d) daemons.set(d.daemonId, d);
      return;
    }
    case "daemons.remove": {
      const d = parseSafe<{ daemonId: string }>(row.new_value);
      if (d) daemons.delete(d.daemonId);
      return;
    }
    case "shards.add": {
      const s = parseSafe<ShardEntry>(row.new_value);
      if (s) shards.set(s.shardId, s);
      return;
    }
    case "shards.remove": {
      const s = parseSafe<{ shardId: string }>(row.new_value);
      if (s) shards.delete(s.shardId);
      return;
    }
    case "shards.decrypt": {
      const s = parseSafe<{ shardId: string }>(row.new_value);
      if (s) {
        const existing = shards.get(s.shardId);
        if (existing) existing.decrypted = true;
      }
      return;
    }
    case "counters.breach": {
      const c = parseSafe<{ tier: string; outcome: "success" | "partial" | "fail" }>(row.new_value);
      if (!c) return;
      const bucket = (snapshot.counters.breaches[c.tier] ??= { success: 0, partial: 0, fail: 0 });
      bucket[c.outcome] += 1;
      return;
    }
    case "counters.alert": {
      const c = parseSafe<{ suppressed: boolean }>(row.new_value);
      if (!c) return;
      if (c.suppressed) snapshot.counters.alertsSuppressed += 1;
      else snapshot.counters.alertsSent += 1;
      return;
    }
    case "counters.blocked": {
      const c = parseSafe<{ reason: string }>(row.new_value);
      if (!c) return;
      snapshot.counters.breachesBlocked[c.reason] = (snapshot.counters.breachesBlocked[c.reason] ?? 0) + 1;
      return;
    }
  }
}

function applyScalar(snapshot: CharacterSnapshot, field: Field, newValue: string | null) {
  if (newValue === null) return;
  switch (field) {
    case "balance":
      snapshot.balance = Number(newValue);
      return;
    case "ramCapacity":
      snapshot.ramCapacity = Number(newValue);
      return;
    case "callsign":
      snapshot.callsign = newValue;
      return;
    case "faction":
      snapshot.faction = newValue;
      return;
  }
}
