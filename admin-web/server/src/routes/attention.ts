import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { computeAttention } from "../lib/attention.js";
import { requireMaster } from "../lib/auth.js";

/** GET /api/attention — панель «требует внимания» на Обзоре. */
export function registerAttentionRoute(app: FastifyInstance, db: Db) {
  app.get("/api/attention", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const items = computeAttention(db);
    return {
      items,
      counts: {
        crit: items.filter((i) => i.severity === "crit").length,
        warn: items.filter((i) => i.severity === "warn").length,
        info: items.filter((i) => i.severity === "info").length,
      },
    };
  });
}
