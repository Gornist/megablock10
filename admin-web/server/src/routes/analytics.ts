import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { buildFactionRows, computeEconomy, computeFactionEvents } from "../lib/analytics.js";
import { requireMaster } from "../lib/auth.js";
import { cachedByDbVersion } from "../lib/dbCache.js";
import { getPlayerBase, withOnline } from "../lib/playerSummary.js";

/** GET /api/economy, GET /api/factions — срезы для управления игрой (не «что произошло», а «как идёт экономика и кто с кем»). */
export function registerAnalyticsRoutes(app: FastifyInstance, db: Db) {
  const cachedEconomy = cachedByDbVersion(db, () => computeEconomy(db, getPlayerBase(db)));
  const cachedFactionEvents = cachedByDbVersion(db, () => computeFactionEvents(db, getPlayerBase(db)));

  app.get("/api/economy", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    return cachedEconomy();
  });

  app.get("/api/factions", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    // Тяжёлая часть (скан истории) кэшируется; online зависит от текущего времени — считается заново.
    return buildFactionRows(withOnline(getPlayerBase(db)), cachedFactionEvents());
  });
}
