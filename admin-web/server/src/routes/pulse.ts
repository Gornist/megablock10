import type { FastifyInstance } from "fastify";
import type { Pulse } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { PULSE_INTERVAL_MS, readPulse } from "../lib/pulse.js";

/** GET /api/pulse?minutes=60 — сэмплы пульса игры (по минутам) для графиков на Обзоре. */
export function registerPulseRoute(app: FastifyInstance, db: Db) {
  app.get<{ Querystring: { minutes?: string } }>("/api/pulse", async (request, reply): Promise<Pulse | void> => {
    if (!requireMaster(db, request, reply)) return;
    const minutes = Math.min(24 * 60, Math.max(1, Number(request.query.minutes) || 60));
    return { intervalMs: PULSE_INTERVAL_MS, samples: readPulse(db, minutes * 60_000) };
  });
}
