import { presentSince } from "../lib/presence.js";
import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { parseSafe } from "../lib/json.js";
import { cachedByDbVersion } from "../lib/dbCache.js";

const ONLINE_WINDOW_MS = 5 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
/**
 * Верхняя граница на скан истории тревог СБ при подсчёте alerts.sent/
 * suppressed — раньше запрос без LIMIT/WHERE перебирал ВСЮ таблицу changes
 * по мере роста истории игры. Сотен записей о тревогах за одну игру более
 * чем достаточно; если их когда-нибудь окажется больше — считаем по самым
 * свежим (то же допущение, что и у HOUR_MS для взломов).
 */
const ALERTS_SCAN_LIMIT = 2000;

/** Части сводки, зависящие только от БД — годятся под cachedByDbVersion (см. players.ts/nodes.ts/slots.ts). */
function computeOverviewBase(db: Db) {
  const totalPlayers = (db.prepare(`SELECT COUNT(DISTINCT subject_key) AS n FROM changes`).get() as { n: number }).n;

  const alertRows = db
    .prepare(`SELECT new_value AS payload FROM changes WHERE field = 'counters.alert' ORDER BY happened_at DESC LIMIT ?`)
    .all(ALERTS_SCAN_LIMIT) as { payload: string | null }[];
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

  return { totalPlayers, alertsSent, alertsSuppressed, slotsPrinted, slotsClaimed };
}

/** GET /api/overview (§7, §8.1 ТЗ) и GET /api/changes/recent (лента изменений — замена SSE на polling, упрощение №3). */
export function registerOverviewRoutes(app: FastifyInstance, db: Db) {
  // См. players.ts/dbCache.ts — кэшируем только то, что зависит от БД, а не
  // от текущего времени: online и "за последний час" считаются заново на
  // каждый запрос из свежего Date.now(), иначе они бы застыли между
  // записями в БД (то же рассуждение, что и у online в players.ts).
  const cachedBase = cachedByDbVersion(db, () => computeOverviewBase(db));

  app.get("/api/overview", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const now = Date.now();
    // «На связи» = были свежие записи ИЛИ heartbeat телефона (пустой батч), причём только игроки, которых мы уже знаем по истории.
    const online = new Set(
      (db.prepare(`SELECT DISTINCT subject_key FROM changes WHERE received_at > ?`).all(now - ONLINE_WINDOW_MS) as { subject_key: string }[]).map(
        (r) => r.subject_key,
      ),
    );
    for (const key of presentSince(now - ONLINE_WINDOW_MS)) {
      if (db.prepare(`SELECT 1 FROM changes WHERE subject_key = ? LIMIT 1`).get(key)) online.add(key);
    }
    const onlinePlayers = online.size;

    const breachRows = db
      .prepare(`SELECT new_value AS payload FROM changes WHERE field = 'counters.breach' AND happened_at > ?`)
      .all(now - HOUR_MS) as { payload: string | null }[];
    const breachesLastHour = { success: 0, partial: 0, fail: 0 };
    for (const row of breachRows) {
      const parsed = parseSafe<{ outcome: "success" | "partial" | "fail" }>(row.payload);
      if (parsed) breachesLastHour[parsed.outcome] += 1;
    }

    const base = cachedBase();

    return {
      players: { online: onlinePlayers, total: base.totalPlayers },
      breachesLastHour,
      slots: { claimed: base.slotsClaimed, printed: base.slotsPrinted },
      alerts: { sent: base.alertsSent, suppressed: base.alertsSuppressed },
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
    // '>=' и курсор = received_at последней ОТДАННОЙ записи (а не серверное "сейчас"): раньше при
    // числе новых записей больше limit остаток терялся навсегда, а запись, вставленная в ту же
    // миллисекунду, что и "now", выпадала из ленты. Повторы на границе клиент отсекает по id.
    const rows = db
      .prepare(`SELECT * FROM changes WHERE received_at >= ? ORDER BY received_at ASC LIMIT ?`)
      .all(since, limit) as { received_at: number }[];
    const cursor = rows.length === limit ? rows[rows.length - 1].received_at : Date.now();
    return { records: rows, now: cursor };
  });
}
