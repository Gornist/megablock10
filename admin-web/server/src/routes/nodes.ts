import type { FastifyInstance } from "fastify";
import { escapeLike } from "../lib/sqlLike.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { parseSafe } from "../lib/json.js";
import { cachedByDbVersion } from "../lib/dbCache.js";
import { makeSlotRef } from "../lib/slotRef.js";
import { containerIdOf } from "../lib/humanize.js";
import type { ContainerSlot } from "./containers.js";

interface ContainerRow {
  id: string;
  name: string;
  tier: string;
  owner_faction: string | null;
  slots_json: string;
}

/**
 * containerId сам по себе (сигналы без привязки к слоту/попытке), или
 * "containerId#slotIndex" (slotRef, см. lib/slotRef.ts), или
 * "containerId:seed" (attemptId — см. BreachScreen.kt, генерируется на
 * попытку взлома, отдельная от slotRef схема и с ней никак не связана,
 * т.к. attemptId никогда не парсится обратно, в отличие от slotRef).
 */
export function containerRefClause(): string {
  return "(source_ref = ? OR source_ref LIKE ? ESCAPE '\\' OR source_ref LIKE ? ESCAPE '\\')";
}
export function containerRefParams(containerId: string): [string, string, string] {
  const escaped = escapeLike(containerId);
  return [containerId, `${escaped}#%`, `${escaped}:%`];
}

/** Переиспользуется и роутом, и CSV-экспортом (routes/exportCsv.ts) — раньше экспорт пересчитывал то же самое отдельно, рискуя разойтись с тем, что видно в Узлах. */
export function listNodeSummaries(db: Db) {
  const containers = db.prepare(`SELECT id, name, tier, owner_faction, slots_json FROM containers`).all() as ContainerRow[];
  return containers.map((c) => summarize(db, c));
}

const nodeCaches = new WeakMap<Db, () => ReturnType<typeof listNodeSummaries>>();

/** Сводка узлов, кэшированная по версии БД — общая для списка узлов и панели «требует внимания». */
export function getNodeSummaries(db: Db) {
  let cached = nodeCaches.get(db);
  if (!cached) {
    cached = cachedByDbVersion(db, () => listNodeSummaries(db));
    nodeCaches.set(db, cached);
  }
  return cached();
}

const HOUR_MS = 60 * 60 * 1000;

/** Сколько взломов узла за последний час — по узлам, у которых они были. Зависит от времени, поэтому вне кэша. */
export function breachesLastHourByNode(db: Db, now = Date.now()): Map<string, number> {
  const rows = db
    .prepare(`SELECT source_ref FROM changes WHERE field = 'counters.breach' AND happened_at > ?`)
    .all(now - HOUR_MS) as { source_ref: string | null }[];
  const out = new Map<string, number>();
  for (const r of rows) {
    const id = containerIdOf(r.source_ref);
    if (id) out.set(id, (out.get(id) ?? 0) + 1);
  }
  return out;
}

/** Исходы взломов узла по часам (последние `hours`, включая пустые) — «когда и как ломали». */
function nodeTimeline(db: Db, containerId: string, hours: number, now = Date.now()) {
  const from = Math.floor(now / HOUR_MS) * HOUR_MS - (hours - 1) * HOUR_MS;
  const buckets = Array.from({ length: hours }, (_, i) => ({ t: from + i * HOUR_MS, success: 0, partial: 0, fail: 0 }));
  const rows = db
    .prepare(`SELECT happened_at, new_value FROM changes WHERE field = 'counters.breach' AND happened_at >= ? AND ${containerRefClause()}`)
    .all(from, ...containerRefParams(containerId)) as { happened_at: number; new_value: string | null }[];
  for (const r of rows) {
    const outcome = parseSafe<{ outcome?: "success" | "partial" | "fail" }>(r.new_value)?.outcome;
    const bucket = buckets[Math.floor((r.happened_at - from) / HOUR_MS)];
    if (bucket && outcome) bucket[outcome] += 1;
  }
  return buckets;
}

/** GET /api/nodes, GET /api/nodes/:id — агрегат по контейнерам (§8.4 ТЗ). Узел = контейнер. */
export function registerNodesRoutes(app: FastifyInstance, db: Db) {
  // См. players.ts/dbCache.ts — кэш по версии БД, не по времени: правка
  // мастера или новый взлом видны на следующем же запросе, не через окно TTL.
  // «За последний час» зависит от текущего времени — добавляется поверх кэша.
  app.get("/api/nodes", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const lastHour = breachesLastHourByNode(db);
    return getNodeSummaries(db).map((n) => ({ ...n, breachesLastHour: lastHour.get(n.id) ?? 0 }));
  });

  app.get<{ Params: { id: string }; Querystring: { hours?: string } }>("/api/nodes/:id", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const c = db.prepare(`SELECT id, name, tier, owner_faction, slots_json FROM containers WHERE id = ?`).get(request.params.id) as
      | ContainerRow
      | undefined;
    if (!c) return reply.code(404).send({ error: "unknown container" });

    const breachers = db
      .prepare(
        `SELECT actor, MAX(happened_at) AS lastAt, COUNT(*) AS n
         FROM changes
         WHERE reason IN ('BREACH_ATTEMPT', 'BREACH_LOOT') AND ${containerRefClause()}
         GROUP BY actor
         ORDER BY lastAt DESC`,
      )
      .all(...containerRefParams(c.id));

    const hours = Math.min(168, Math.max(1, Number(request.query.hours) || 24));
    return { ...summarize(db, c), breachers, timeline: nodeTimeline(db, c.id, hours) };
  });
}

function summarize(db: Db, c: ContainerRow) {
  const slots = JSON.parse(c.slots_json) as ContainerSlot[];
  const slotsTotal = slots.filter((s) => s.copies > 0).reduce((sum, s) => sum + s.copies, 0);
  const slotRefs = slots.filter((s) => s.copies > 0).map((s) => makeSlotRef(c.id, s.index));
  const slotsClaimed =
    slotRefs.length === 0
      ? 0
      : (db
          .prepare(
            `SELECT COUNT(*) AS n FROM slot_claims WHERE revoked = 0 AND slot_ref IN (${slotRefs.map(() => "?").join(",")})`,
          )
          .get(...slotRefs) as { n: number }).n;

  const breachCounts = db
    .prepare(`SELECT new_value AS payload FROM changes WHERE field = 'counters.breach' AND ${containerRefClause()}`)
    .all(...containerRefParams(c.id)) as { payload: string | null }[];
  let success = 0,
    partial = 0,
    fail = 0;
  for (const row of breachCounts) {
    const parsed = parseSafe<{ outcome: "success" | "partial" | "fail" }>(row.payload);
    if (!parsed) continue;
    if (parsed.outcome === "success") success += 1;
    else if (parsed.outcome === "partial") partial += 1;
    else fail += 1;
  }

  const uniquePlayers = (
    db
      .prepare(
        `SELECT COUNT(DISTINCT actor) AS n FROM changes WHERE reason IN ('BREACH_ATTEMPT', 'BREACH_LOOT') AND ${containerRefClause()}`,
      )
      .get(...containerRefParams(c.id)) as { n: number }
  ).n;

  const alerts = db
    .prepare(`SELECT new_value AS payload FROM changes WHERE field = 'counters.alert' AND ${containerRefClause()}`)
    .all(...containerRefParams(c.id)) as { payload: string | null }[];
  let alertsSent = 0,
    alertsSuppressed = 0;
  for (const row of alerts) {
    const parsed = parseSafe<{ suppressed: boolean }>(row.payload);
    if (!parsed) continue;
    if (parsed.suppressed) alertsSuppressed += 1;
    else alertsSent += 1;
  }

  const lastBreach = db
    .prepare(
      `SELECT MAX(happened_at) AS at FROM changes WHERE reason IN ('BREACH_ATTEMPT', 'BREACH_LOOT') AND ${containerRefClause()}`,
    )
    .get(...containerRefParams(c.id)) as { at: number | null };

  return {
    id: c.id,
    name: c.name,
    tier: c.tier,
    ownerFaction: c.owner_faction,
    slotsTotal,
    slotsClaimed,
    breaches: { success, partial, fail },
    uniquePlayers,
    alertsSent,
    alertsSuppressed,
    lastBreachAt: lastBreach.at,
  };
}
