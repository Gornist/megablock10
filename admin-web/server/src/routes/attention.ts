import type { FastifyInstance } from "fastify";
import type { Attention } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { replayAnomalies } from "../lib/anomalies.js";
import { computeAttention } from "../lib/attention.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { makeHumanizeContext } from "../lib/humanize.js";

const MAX_SNOOZE_MIN = 24 * 60;
const MAX_REPLAY_STEPS = 2000;

/** Панель «требует внимания» на Обзоре, отложенные тревоги и перебор детекторов по прошлому. */
export function registerAttentionRoute(app: FastifyInstance, db: Db) {
  app.get<{ Querystring: { all?: string } }>("/api/attention", async (request, reply): Promise<Attention | void> => {
    if (!requireMaster(db, request, reply)) return;
    const now = Date.now();
    db.prepare(`DELETE FROM attention_snooze WHERE until <= ?`).run(now);
    const snoozed = new Set((db.prepare(`SELECT item_id FROM attention_snooze`).all() as { item_id: string }[]).map((r) => r.item_id));

    const all = computeAttention(db);
    const items = request.query.all === "1" ? all : all.filter((i) => !snoozed.has(i.id));
    return {
      items,
      snoozed: all.length - items.length,
      counts: {
        crit: items.filter((i) => i.severity === "crit").length,
        warn: items.filter((i) => i.severity === "warn").length,
        info: items.filter((i) => i.severity === "info").length,
      },
    };
  });

  /** «Знаю, не мешай»: тревога молчит N минут (минуты = 0 — вернуть сразу). Вернётся сама, если условие сохранится после срока. */
  app.post<{ Body: { id?: unknown; minutes?: unknown } }>("/api/attention/snooze", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const { id, minutes } = request.body ?? {};
    if (typeof id !== "string" || id === "" || id.length > 400) return reply.code(400).send({ error: "id is required" });
    if (typeof minutes !== "number" || !Number.isFinite(minutes) || minutes < 0 || minutes > MAX_SNOOZE_MIN) {
      return reply.code(400).send({ error: `minutes must be a number from 0 to ${MAX_SNOOZE_MIN}` });
    }
    if (minutes === 0) {
      db.prepare(`DELETE FROM attention_snooze WHERE item_id = ?`).run(id);
      return { ok: true, until: null };
    }
    const until = Date.now() + Math.round(minutes) * 60_000;
    db.prepare(`INSERT OR REPLACE INTO attention_snooze (item_id, until) VALUES (?, ?)`).run(id, until);
    const title = computeAttention(db).find((i) => i.id === id)?.title;
    logMasterAction(db, master.id, "ATTENTION_SNOOZE", { id, title, minutes: Math.round(minutes) });
    return { ok: true, until };
  });

  /**
   * GET /api/anomalies/replay?from=&to=&stepMin= — «что показали бы мастеру» по прошлому (пульс + записи), эпизодами.
   * Для подбора порогов ANOM_* по записанным играм и стендовым прогонам.
   */
  app.get<{ Querystring: { from?: string; to?: string; stepMin?: string } }>("/api/anomalies/replay", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const to = Number(request.query.to) || Date.now();
    const from = Number(request.query.from) || to - 6 * 60 * 60_000;
    const stepMs = Math.max(1, Number(request.query.stepMin) || 1) * 60_000;
    if (from >= to) return reply.code(400).send({ error: "from must be earlier than to" });
    if ((to - from) / stepMs > MAX_REPLAY_STEPS) return reply.code(400).send({ error: `too many steps, max ${MAX_REPLAY_STEPS}: raise stepMin or narrow the range` });
    return { from, to, stepMs, episodes: replayAnomalies(db, makeHumanizeContext(db).playerName, from, to, stepMs) };
  });
}
