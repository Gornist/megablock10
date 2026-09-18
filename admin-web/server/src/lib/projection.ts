import type { Db } from "../db/index.js";
import type { Field, StoredChangeRow } from "./changeRecord.js";
import { RAM_CAPACITY_DEFAULT } from "./identityDefaults.js";
import { parseSafe } from "./json.js";

export interface DaemonEntry {
  daemonId: string;
  name: string;
  tier: string;
  weight: number;
  acquiredAt: number;
  sourceRef: string | null;
}

export interface ShardEntry {
  shardId: string;
  title: string;
  tier: string;
  decrypted: boolean;
  acquiredAt: number;
  sourceRef: string | null;
}

export interface Counters {
  breaches: Record<string, { success: number; partial: number; fail: number }>;
  slotsClaimed: number;
  alertsSent: number;
  alertsSuppressed: number;
  breachesBlocked: Record<string, number>;
}

export interface CharacterSnapshot {
  publicKeyB64: string;
  callsign: string;
  faction: string;
  ramCapacity: number;
  balance: number;
  daemons: DaemonEntry[];
  shards: ShardEntry[];
  counters: Counters;
  lastSeenAt: number;
  lastSeq: number;
}

const SCALAR_FIELDS: Field[] = ["balance", "ramCapacity", "callsign", "faction"];

function emptyCounters(): Counters {
  return { breaches: {}, slotsClaimed: 0, alertsSent: 0, alertsSuppressed: 0, breachesBlocked: {} };
}

/**
 * Снимок персонажа, посчитанный SQL-выборкой по changes на каждое чтение —
 * никакой отдельной таблицы-снимка нет и поддерживать её в синхроне не
 * нужно (см. обсуждение объёма работ). Для ~100 игроков и десятков тысяч
 * записей это дешевле, чем инкрементальное обновление, и не может разойтись
 * с историей по определению — история и есть источник истины.
 *
 * Формат JSON внутри old_value/new_value для полей daemons, shards, counters
 * — рабочий черновик протокола, будет зафиксирован вместе с Android-клиентом
 * (Ф2): daemons.add/shards.add несут полный объект сущности, .remove/.decrypt
 * несут { daemonId | shardId }, counters.* несут { path, delta }.
 */
export function projectCharacter(db: Db, subjectKeyB64: string): CharacterSnapshot | null {
  // received_at, не seq — seq осмысленно сравним только внутри одного actor'а
  // (устройство нумерует свои же записи по порядку), а master-правки живут в
  // отдельном (отрицательном) диапазоне seq именно чтобы не сталкиваться с
  // устройством, а не чтобы задавать порядок применения. received_at общий
  // для всех источников и отражает реальный порядок поступления на сервер —
  // то, что нужно для "последняя правка выигрывает" (§6.4 ТЗ).
  const rows = db
    .prepare(`SELECT * FROM changes WHERE subject_key = ? ORDER BY received_at ASC, seq ASC`)
    .all(subjectKeyB64) as StoredChangeRow[];

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
  };

  const daemons = new Map<string, DaemonEntry>();
  const shards = new Map<string, ShardEntry>();

  for (const row of rows) {
    applyRow(snapshot, daemons, shards, row);
    snapshot.lastSeenAt = Math.max(snapshot.lastSeenAt, row.received_at);
    snapshot.lastSeq = Math.max(snapshot.lastSeq, row.seq);
  }

  snapshot.daemons = [...daemons.values()];
  snapshot.shards = [...shards.values()];

  // slotsClaimed — не из changes, а из реестра арбитража (§5 ТЗ): именно
  // slot_claims фиксирует, кто реально получил тиражный слот через сервер.
  const claimedRow = db
    .prepare(`SELECT COUNT(*) AS n FROM slot_claims WHERE claimant_key = ? AND revoked = 0`)
    .get(subjectKeyB64) as { n: number };
  snapshot.counters.slotsClaimed = claimedRow.n;

  return snapshot;
}

function applyRow(
  snapshot: CharacterSnapshot,
  daemons: Map<string, DaemonEntry>,
  shards: Map<string, ShardEntry>,
  row: StoredChangeRow,
) {
  const field = row.field as Field;

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
