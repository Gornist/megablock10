import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { REASONS } from "../lib/changeRecord.js";
import { withHuman } from "../lib/humanize.js";
import { getPlayerBase } from "../lib/playerSummary.js";
import { containerRefClause, containerRefParams } from "./nodes.js";

/** Значение фильтра фракции для игроков без фракции (пустую строку в query не передать). */
export const NO_FACTION = "__none__";

const M = "reason = 'MASTER_OVERRIDE'";
/**
 * Типы событий — те же группы, что цветные маркеры в ленте (humanize.ts,
 * ChangeKind): деньги, предметы, взломы, сигналы СБ, действия мастера, прочее.
 * Считаются по полю и причине записи, поэтому фильтр совпадает с тем, что
 * мастер видит на экране.
 */
export const KIND_SQL: Record<string, string> = {
  money: `(field = 'balance' AND NOT ${M})`,
  item: `(field IN ('daemons.add','daemons.remove','shards.add','shards.remove','shards.decrypt') AND NOT ${M})`,
  breach: `field IN ('counters.breach','counters.blocked')`,
  alert: `field = 'counters.alert'`,
  master: M,
  system: `(field IN ('callsign','faction','ramCapacity') AND NOT ${M})`,
};

/**
 * GET /api/events — журнал событий с фильтрами: по игроку, фракции (текущей),
 * типу, причине, узлу и времени, с пагинацией. Живая лента Обзора показывает
 * «всё подряд»; здесь можно спросить «что делала Alice», «что натворила
 * фракция NEON», «кто ломал Насосную-4 за последний час».
 */
export function registerEventsRoute(app: FastifyInstance, db: Db) {
  app.get<{
    Querystring: { player?: string; faction?: string; kind?: string; reason?: string; node?: string; since?: string; until?: string; page?: string; pageSize?: string };
  }>("/api/events", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const q = request.query;

    const clauses: string[] = [];
    const params: unknown[] = [];

    if (q.kind) {
      if (!(q.kind in KIND_SQL)) return reply.code(400).send({ error: `kind must be one of: ${Object.keys(KIND_SQL).join(", ")}` });
      clauses.push(KIND_SQL[q.kind]);
    }
    if (q.reason) {
      if (!(REASONS as readonly string[]).includes(q.reason)) return reply.code(400).send({ error: "unknown reason" });
      clauses.push("reason = ?");
      params.push(q.reason);
    }
    if (q.player) {
      clauses.push("subject_key = ?");
      params.push(q.player);
    } else {
      // Объявление — по записи на каждого адресата: в общем потоке это сотня одинаковых строк, они живут на экране «Объявления».
      clauses.push("field != 'announcement'");
    }
    if (q.faction) {
      const keys = getPlayerBase(db)
        .filter((p) => p.faction === (q.faction === NO_FACTION ? "" : q.faction))
        .map((p) => p.publicKeyB64);
      if (keys.length === 0) return { total: 0, page: 0, pageSize: 0, records: [] };
      clauses.push(`subject_key IN (${keys.map(() => "?").join(",")})`);
      params.push(...keys);
    }
    if (q.node) {
      clauses.push(containerRefClause());
      params.push(...containerRefParams(q.node));
    }
    const since = Number(q.since);
    if (q.since && Number.isFinite(since)) {
      clauses.push("received_at >= ?");
      params.push(since);
    }
    const until = Number(q.until);
    if (q.until && Number.isFinite(until)) {
      clauses.push("received_at <= ?");
      params.push(until);
    }

    const pageSize = Math.min(200, Math.max(1, Number(q.pageSize) || 50));
    const page = Math.max(0, Number(q.page) || 0);
    const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";

    const total = (db.prepare(`SELECT COUNT(*) AS n FROM changes ${where}`).get(...params) as { n: number }).n;
    const rows = db
      .prepare(`SELECT * FROM changes ${where} ORDER BY received_at DESC, seq DESC LIMIT ? OFFSET ?`)
      .all(...params, pageSize, page * pageSize);
    return { total, page, pageSize, records: withHuman(db, rows as never[]) };
  });
}
