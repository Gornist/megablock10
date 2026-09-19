import type { FastifyInstance } from "fastify";
import { escapeLike } from "../lib/sqlLike.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { parseSafe } from "../lib/json.js";
import { cachedByDbVersion } from "../lib/dbCache.js";
import { makeSlotRef } from "../lib/slotRef.js";
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
function containerRefClause(): string {
  return "(source_ref = ? OR source_ref LIKE ? ESCAPE '\\' OR source_ref LIKE ? ESCAPE '\\')";
}
function containerRefParams(containerId: string): [string, string, string] {
  const escaped = escapeLike(containerId);
  return [containerId, `${escaped}#%`, `${escaped}:%`];
}

/** Переиспользуется и роутом, и CSV-экспортом (routes/exportCsv.ts) — раньше экспорт пересчитывал то же самое отдельно, рискуя разойтись с тем, что видно в Узлах. */
export function listNodeSummaries(db: Db) {
  const containers = db.prepare(`SELECT id, name, tier, owner_faction, slots_json FROM containers`).all() as ContainerRow[];
  return containers.map((c) => summarize(db, c));
}

/** GET /api/nodes, GET /api/nodes/:id — агрегат по контейнерам (§8.4 ТЗ). Узел = контейнер. */
export function registerNodesRoutes(app: FastifyInstance, db: Db) {
  // См. players.ts/dbCache.ts — кэш по версии БД, не по времени: правка
  // мастера или новый взлом видны на следующем же запросе, не через окно TTL.
  const cachedNodeSummaries = cachedByDbVersion(db, () => listNodeSummaries(db));

  app.get("/api/nodes", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    return cachedNodeSummaries();
  });

  app.get<{ Params: { id: string } }>("/api/nodes/:id", async (request, reply) => {
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

    return { ...summarize(db, c), breachers };
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
