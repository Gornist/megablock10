import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { AUDIT_ACTION_LABEL_RU, describeAudit } from "../lib/auditSummary.js";
import { makeHumanizeContext } from "../lib/humanize.js";
import { parseSafe } from "../lib/json.js";

/**
 * GET /api/audit — журнал действий мастеров (audit_master пишется с самого
 * начала, но читать его было нечем). На игре с несколькими мастерами это
 * вопрос доверия: «кто мне обнулил баланс?» — ответ здесь, с основанием.
 */
export function registerAuditRoute(app: FastifyInstance, db: Db) {
  app.get<{ Querystring: { action?: string; page?: string; pageSize?: string } }>("/api/audit", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const pageSize = Math.min(200, Math.max(1, Number(request.query.pageSize) || 50));
    const page = Math.max(0, Number(request.query.page) || 0);
    const action = request.query.action || null;

    const where = action ? "WHERE a.action = ?" : "";
    const params = action ? [action] : [];
    const total = (db.prepare(`SELECT COUNT(*) AS n FROM audit_master a ${where}`).get(...params) as { n: number }).n;
    const rows = db
      .prepare(
        `SELECT a.id, a.action, a.detail, a.at, m.name AS masterName
         FROM audit_master a LEFT JOIN masters m ON m.id = a.master_id
         ${where} ORDER BY a.at DESC LIMIT ? OFFSET ?`,
      )
      .all(...params, pageSize, page * pageSize) as { id: string; action: string; detail: string | null; at: number; masterName: string | null }[];

    const ctx = makeHumanizeContext(db);
    const actions = (db.prepare(`SELECT DISTINCT action FROM audit_master ORDER BY action`).all() as { action: string }[]).map((r) => ({
      action: r.action,
      label: AUDIT_ACTION_LABEL_RU[r.action] ?? r.action,
    }));

    return {
      total,
      page,
      pageSize,
      actions,
      records: rows.map((r) => {
        const detail = parseSafe<Record<string, unknown>>(r.detail);
        return {
          id: r.id,
          at: r.at,
          action: r.action,
          actionLabel: AUDIT_ACTION_LABEL_RU[r.action] ?? r.action,
          masterName: r.masterName ?? "неизвестный мастер",
          summary: describeAudit(r.action, detail, ctx.playerName),
        };
      }),
    };
  });
}
