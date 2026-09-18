import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { parseSafe } from "../lib/json.js";

const ONLINE_WINDOW_MS = 5 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

/** GET /api/overview (§7, §8.1 ТЗ) и GET /api/changes/recent (лента изменений — замена SSE на polling, упрощение №3). */
export function registerOverviewRoutes(app: FastifyInstance, db: Db) {
  app.get("/api/overview", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const now = Date.now();
    const totalPlayers = (db.prepare(`SELECT COUNT(DISTINCT subject_key) AS n FROM changes`).get() as { n: number }).n;
    const onlinePlayers = (
      db.prepare(`SELECT COUNT(DISTINCT subject_key) AS n FROM changes WHERE received_at > ?`).get(now - ONLINE_WINDOW_MS) as {
        n: number;
      }
    ).n;

    const breachRows = db
      .prepare(`SELECT new_value AS payload FROM changes WHERE field = 'counters.breach' AND happened_at > ?`)
      .all(now - HOUR_MS) as { payload: string | null }[];
    const breachesLastHour = { success: 0, partial: 0, fail: 0 };
    for (const row of breachRows) {
      const parsed = parseSafe<{ outcome: "success" | "partial" | "fail" }>(row.payload);
      if (parsed) breachesLastHour[parsed.outcome] += 1;
    }

    const alertRows = db.prepare(`SELECT new_value AS payload FROM changes WHERE field = 'counters.alert'`).all() as {
      payload: string | null;
    }[];
    let alertsSent = 0,
      alertsSuppressed = 0;
    for (const row of alertRows) {
      const parsed = parseSafe<{ suppressed: boolean }>(row.payload);
      if (!parsed) continue;
      if (parsed.suppressed) alertsSuppressed += 1;
      else alertsSent += 1;
    }

    const slotsPrinted = (
      db.prepare(`SELECT slots_json FROM containers`).all() as { slots_json: string }[]
    ).reduce((sum, c) => {
      const slots = JSON.parse(c.slots_json) as { copies: number }[];
      return sum + slots.filter((s) => s.copies > 0).reduce((n, s) => n + s.copies, 0);
    }, 0);
    const slotsClaimed = (db.prepare(`SELECT COUNT(*) AS n FROM slot_claims WHERE revoked = 0`).get() as { n: number }).n;

    return {
      players: { online: onlinePlayers, total: totalPlayers },
      breachesLastHour,
      slots: { claimed: slotsClaimed, printed: slotsPrinted },
      alerts: { sent: alertsSent, suppressed: alertsSuppressed },
    };
  });

  /**
   * GET /api/changes/recent?since=<ms> — живая лента для 8.1, на polling
   * вместо SSE. Фронт дёргает раз в 2-3с с последним увиденным received_at.
   */
  app.get<{ Querystring: { since?: string; limit?: string } }>("/api/changes/recent", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const since = Number(request.query.since) || 0;
    const limit = Math.min(500, Math.max(1, Number(request.query.limit) || 100));
    const rows = db
      .prepare(`SELECT * FROM changes WHERE received_at > ? ORDER BY received_at ASC LIMIT ?`)
      .all(since, limit);
    return { records: rows, now: Date.now() };
  });
}
