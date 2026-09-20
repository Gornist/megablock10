import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import {
  breachesLastHourByNode,
  containerRefClause,
  containerRefParams,
  getNodeSummaries,
  nodeTimeline,
} from "../lib/nodeSummary.js";

/** GET /api/nodes, GET /api/nodes/:id — агрегат по контейнерам (§8.4 ТЗ). Узел = контейнер. Сама сводка — lib/nodeSummary.ts. */
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

    const summary = getNodeSummaries(db).find((n) => n.id === request.params.id);
    if (!summary) return reply.code(404).send({ error: "unknown container" });

    const breachers = db
      .prepare(
        `SELECT actor, MAX(received_at) AS lastAt, COUNT(*) AS n
         FROM changes
         WHERE reason IN ('BREACH_ATTEMPT', 'BREACH_LOOT') AND ${containerRefClause()}
         GROUP BY actor
         ORDER BY lastAt DESC`,
      )
      .all(...containerRefParams(summary.id));

    const hours = Math.min(168, Math.max(1, Number(request.query.hours) || 24));
    return { ...summary, breachers, timeline: nodeTimeline(db, summary.id, hours) };
  });
}
