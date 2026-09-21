import type { NodeSummary } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import type { ContainerSlot } from "./containerSlots.js";
import { cachedByDbVersion } from "./dbCache.js";
import { containerIdOfSourceRef } from "./humanize.js";
import { parseSafe } from "./json.js";
import { escapeLike } from "./sqlLike.js";
import { makeSlotRef } from "./slotRef.js";

interface ContainerRow {
  id: string;
  name: string;
  tier: string;
  owner_faction: string | null;
  slots_json: string;
}

const HOUR_MS = 60 * 60 * 1000;

/**
 * containerId сам по себе (сигналы без привязки к слоту/попытке), или
 * "containerId#slotIndex" (slotRef, см. lib/slotRef.ts), или
 * "containerId:seed" (attemptId — см. BreachScreen.kt, генерируется на
 * попытку взлома, отдельная от slotRef схема и с ней никак не связана,
 * т.к. attemptId никогда не парсится обратно, в отличие от slotRef).
 * SQL-вариант — для точечных запросов по одному узлу (детали узла, события).
 */
export function containerRefClause(): string {
  return "(source_ref = ? OR source_ref LIKE ? ESCAPE '\\' OR source_ref LIKE ? ESCAPE '\\')";
}
export function containerRefParams(containerId: string): [string, string, string] {
  const escaped = escapeLike(containerId);
  return [containerId, `${escaped}#%`, `${escaped}:%`];
}

/**
 * Тот же отбор, что containerRefClause, но в памяти — для сводки по ВСЕМ
 * узлам за один проход по истории. id генерируется дашбордом и не содержит
 * ни '#', ни ':' (см. SAFE_ID в routes/master.ts), поэтому владелец записи —
 * всё, что стоит до первого из этих разделителей.
 */
function refToNode(ref: string | null, ids: Set<string>): string | null {
  if (!ref) return null;
  if (ids.has(ref)) return ref;
  const cut = ref.search(/[#:]/);
  if (cut <= 0) return null;
  const candidate = ref.slice(0, cut);
  return ids.has(candidate) ? candidate : null;
}

interface Acc {
  success: number;
  partial: number;
  fail: number;
  players: Set<string>;
  alertsSent: number;
  alertsSuppressed: number;
  lastBreachAt: number | null;
}

/**
 * Сводка по всем узлам. Раньше на каждый узел шло по пять запросов с LIKE по
 * source_ref (индекс на префиксный LIKE с ESCAPE не работает — полный скан на
 * каждый узел): на 100 тыс. записей и 20 узлах это ~800 мс. Теперь одна выборка
 * только релевантных записей и раскладка по узлам в памяти.
 * Переиспользуется и роутом, и CSV-экспортом (routes/exportCsv.ts).
 */
export function listNodeSummaries(db: Db): NodeSummary[] {
  const containers = db.prepare(`SELECT id, name, tier, owner_faction, slots_json FROM containers`).all() as ContainerRow[];
  const ids = new Set(containers.map((c) => c.id));
  const acc = new Map<string, Acc>(
    containers.map((c) => [c.id, { success: 0, partial: 0, fail: 0, players: new Set(), alertsSent: 0, alertsSuppressed: 0, lastBreachAt: null }]),
  );

  const rows = db.prepare(
    `SELECT field, reason, actor, received_at, new_value, source_ref FROM changes
     WHERE source_ref IS NOT NULL AND (field IN ('counters.breach', 'counters.alert') OR reason IN ('BREACH_ATTEMPT', 'BREACH_LOOT'))`,
  );
  for (const r of rows.iterate() as Iterable<{ field: string; reason: string; actor: string; received_at: number; new_value: string | null; source_ref: string }>) {
    const a = acc.get(refToNode(r.source_ref, ids) ?? "");
    if (!a) continue;

    if (r.field === "counters.breach") {
      const outcome = parseSafe<{ outcome?: string }>(r.new_value);
      if (outcome) {
        if (outcome.outcome === "success") a.success += 1;
        else if (outcome.outcome === "partial") a.partial += 1;
        else a.fail += 1;
      }
    } else if (r.field === "counters.alert") {
      const alert = parseSafe<{ suppressed?: boolean }>(r.new_value);
      if (alert) {
        if (alert.suppressed) a.alertsSuppressed += 1;
        else a.alertsSent += 1;
      }
    }
    if (r.reason === "BREACH_ATTEMPT" || r.reason === "BREACH_LOOT") {
      a.players.add(r.actor);
      a.lastBreachAt = Math.max(a.lastBreachAt ?? 0, r.received_at);
    }
  }

  const claimsBySlot = new Map(
    (db.prepare(`SELECT slot_ref, COUNT(*) AS n FROM slot_claims WHERE revoked = 0 GROUP BY slot_ref`).all() as { slot_ref: string; n: number }[]).map((r) => [r.slot_ref, r.n]),
  );

  return containers.map((c) => {
    const slots = JSON.parse(c.slots_json) as ContainerSlot[];
    const limited = slots.filter((s) => s.copies > 0);
    const a = acc.get(c.id)!;
    return {
      id: c.id,
      name: c.name,
      tier: c.tier,
      ownerFaction: c.owner_faction,
      slotsTotal: limited.reduce((sum, s) => sum + s.copies, 0),
      slotsClaimed: limited.reduce((sum, s) => sum + (claimsBySlot.get(makeSlotRef(c.id, s.index)) ?? 0), 0),
      breaches: { success: a.success, partial: a.partial, fail: a.fail },
      uniquePlayers: a.players.size,
      alertsSent: a.alertsSent,
      alertsSuppressed: a.alertsSuppressed,
      lastBreachAt: a.lastBreachAt,
    };
  });
}

const nodeCaches = new WeakMap<Db, () => NodeSummary[]>();

/** Сводка узлов, кэшированная по версии БД — общая для списка узлов и панели «требует внимания». */
export function getNodeSummaries(db: Db) {
  let cached = nodeCaches.get(db);
  if (!cached) {
    cached = cachedByDbVersion(db, () => listNodeSummaries(db));
    nodeCaches.set(db, cached);
  }
  return cached();
}

/**
 * Сколько взломов узла за последний час. По времени СЕРВЕРА (received_at): часы
 * телефонов расходятся, и «за час» по ним даёт разные цифры на Обзоре и в узлах.
 * Зависит от текущего времени, поэтому вне кэша.
 */
export function breachesLastHourByNode(db: Db, now = Date.now()): Map<string, number> {
  const rows = db
    .prepare(`SELECT source_ref FROM changes WHERE field = 'counters.breach' AND received_at > ?`)
    .all(now - HOUR_MS) as { source_ref: string | null }[];
  const out = new Map<string, number>();
  for (const r of rows) {
    const id = containerIdOfSourceRef(r.source_ref);
    if (id) out.set(id, (out.get(id) ?? 0) + 1);
  }
  return out;
}

/** Исходы взломов узла по часам (последние `hours`, включая пустые) — «когда и как ломали». Часы сервера, как и в breachesLastHourByNode. */
export function nodeTimeline(db: Db, containerId: string, hours: number, now = Date.now()) {
  const from = Math.floor(now / HOUR_MS) * HOUR_MS - (hours - 1) * HOUR_MS;
  const buckets = Array.from({ length: hours }, (_, i) => ({ t: from + i * HOUR_MS, success: 0, partial: 0, fail: 0 }));
  const rows = db
    .prepare(`SELECT received_at, new_value FROM changes WHERE field = 'counters.breach' AND received_at >= ? AND ${containerRefClause()}`)
    .all(from, ...containerRefParams(containerId)) as { received_at: number; new_value: string | null }[];
  for (const r of rows) {
    const outcome = parseSafe<{ outcome?: "success" | "partial" | "fail" }>(r.new_value)?.outcome;
    const bucket = buckets[Math.floor((r.received_at - from) / HOUR_MS)];
    if (bucket && outcome) bucket[outcome] += 1;
  }
  return buckets;
}
