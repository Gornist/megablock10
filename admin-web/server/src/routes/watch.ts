import type { FastifyInstance } from "fastify";
import type { WatchItem } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";

const MAX_NOTE = 300;

/**
 * Игроки «под наблюдением» — общий список всех мастеров с пометкой («на
 * разбор», «подозрительный баланс»). Живёт в БД сервера, а не в браузере:
 * другой мастер на другом устройстве видит те же закладки.
 */
export function registerWatchRoutes(app: FastifyInstance, db: Db) {
  app.get("/api/watch", async (request, reply): Promise<WatchItem[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    return db
      .prepare(
        `SELECT w.subject_key AS publicKeyB64, w.note, w.added_at AS addedAt, COALESCE(m.name, '?') AS addedBy
         FROM watchlist w LEFT JOIN masters m ON m.id = w.added_by ORDER BY w.added_at DESC`,
      )
      .all() as WatchItem[];
  });

  app.put<{ Params: { key: string }; Body: { note?: unknown } }>("/api/watch/:key", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const note = request.body?.note ?? "";
    if (typeof note !== "string" || note.length > MAX_NOTE) return reply.code(400).send({ error: `note must be a string up to ${MAX_NOTE}` });
    if (!db.prepare(`SELECT 1 FROM changes WHERE subject_key = ? LIMIT 1`).get(request.params.key)) {
      return reply.code(404).send({ error: "unknown character" });
    }
    db.prepare(
      `INSERT INTO watchlist (subject_key, note, added_by, added_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(subject_key) DO UPDATE SET note = excluded.note`,
    ).run(request.params.key, note.trim(), master.id, Date.now());
    return { ok: true };
  });

  app.delete<{ Params: { key: string } }>("/api/watch/:key", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    db.prepare(`DELETE FROM watchlist WHERE subject_key = ?`).run(request.params.key);
    return { ok: true };
  });
}
