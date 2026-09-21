import type { Db } from "../db/index.js";
import type { Field, StoredChangeRow } from "./changeRecord.js";
import { RAM_CAPACITY_DEFAULT } from "./identityDefaults.js";
import { parseSafe } from "./json.js";

import type { CharacterSnapshot, Counters, DaemonEntry, ShardEntry } from "../apiTypes.js";

export type { CharacterSnapshot, Counters, DaemonEntry, ShardEntry };

/** Поля записи, которые читает свёртка (подмножество StoredChangeRow). */
export type ProjectionRow = Pick<StoredChangeRow, "subject_key" | "field" | "new_value" | "reason" | "received_at" | "seq">;

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
export function projectCharacter(db: Db, subjectKeyB64: string, until?: number): CharacterSnapshot | null {
  // received_at, не seq — seq осмысленно сравним только внутри одного actor'а
  // (устройство нумерует свои же записи по порядку), а master-правки живут в
  // отдельном (отрицательном) диапазоне seq именно чтобы не сталкиваться с
  // устройством, а не чтобы задавать порядок применения. received_at общий
  // для всех источников и отражает реальный порядок поступления на сервер —
  // то, что нужно для "последняя правка выигрывает" (§6.4 ТЗ).
  // until — состояние «на момент T» по часам сервера (received_at): ровно то, что видел бы дашборд в тот момент.
  const rows = (
    until === undefined
      ? db.prepare(`SELECT * FROM changes WHERE subject_key = ? ORDER BY received_at ASC, seq ASC`).all(subjectKeyB64)
      : db
          .prepare(`SELECT * FROM changes WHERE subject_key = ? AND received_at <= ? ORDER BY received_at ASC, seq ASC`)
          .all(subjectKeyB64, until)
  ) as StoredChangeRow[];

  // slotsClaimed — не из changes, а из реестра арбитража (§5 ТЗ): именно
  // slot_claims фиксирует, кто реально получил тиражный слот через сервер.
  const claimedRow = (
    until === undefined
      ? db.prepare(`SELECT COUNT(*) AS n FROM slot_claims WHERE claimant_key = ? AND revoked = 0`).get(subjectKeyB64)
      : db
          .prepare(`SELECT COUNT(*) AS n FROM slot_claims WHERE claimant_key = ? AND revoked = 0 AND claimed_at <= ?`)
          .get(subjectKeyB64, until)
  ) as { n: number };

  return projectRows(subjectKeyB64, rows, claimedRow.n);
}

/**
 * Снимки ВСЕХ персонажей за один проход по истории: одна выборка, упорядоченная
 * по (игрок, время), вместо запроса на каждого игрока (1 + 2·N обращений к БД).
 * Результат тот же, что у projectCharacter для каждого ключа по отдельности
 * (это проверяется тестом) — просто дешевле на сотнях игроков и десятках тысяч записей.
 */
/** Только то, что читает свёртка: подписи, actor, source_ref и т.п. ей не нужны, а на десятках тысяч строк их материализация заметна. */
const PROJECTION_COLUMNS = "subject_key, field, new_value, reason, received_at, seq";

export function projectAll(db: Db, until?: number): CharacterSnapshot[] {
  const claims = new Map(
    (
      (until === undefined
        ? db.prepare(`SELECT claimant_key, COUNT(*) AS n FROM slot_claims WHERE revoked = 0 GROUP BY claimant_key`).all()
        : db.prepare(`SELECT claimant_key, COUNT(*) AS n FROM slot_claims WHERE revoked = 0 AND claimed_at <= ? GROUP BY claimant_key`).all(until)) as {
        claimant_key: string;
        n: number;
      }[]
    ).map((r) => [r.claimant_key, r.n]),
  );

  const stmt =
    until === undefined
      ? db.prepare(`SELECT ${PROJECTION_COLUMNS} FROM changes ORDER BY subject_key, received_at ASC, seq ASC`)
      : db.prepare(`SELECT ${PROJECTION_COLUMNS} FROM changes WHERE received_at <= ? ORDER BY subject_key, received_at ASC, seq ASC`);
  const rows = (until === undefined ? stmt.iterate() : stmt.iterate(until)) as Iterable<ProjectionRow>;

  const out: CharacterSnapshot[] = [];
  let key: string | null = null;
  let group: ProjectionRow[] = [];
  const flush = () => {
    if (key === null) return;
    const snapshot = projectRows(key, group, claims.get(key) ?? 0);
    if (snapshot) out.push(snapshot);
  };
  for (const row of rows) {
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
export function projectRows(subjectKeyB64: string, rows: ProjectionRow[], slotsClaimed: number): CharacterSnapshot | null {
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
