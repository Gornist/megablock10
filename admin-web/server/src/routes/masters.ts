import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { createMaster, logMasterAction, requireMaster } from "../lib/auth.js";

/**
 * GET/POST /api/masters — управление мастерскими аккаунтами прямо из
 * дашборда, не только через `npm run create-master` в терминале на
 * ноутбуке (единственный путь раньше — добавить второго мастера посреди
 * игры без доступа к консоли было нельзя). Токен виден только один раз,
 * в ответе на создание — как и у CLI-скрипта, дальше хранится лишь хэш.
 */
export function registerMastersRoutes(app: FastifyInstance, db: Db) {
  app.get("/api/masters", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    return db.prepare(`SELECT id, name, created_at AS createdAt FROM masters ORDER BY created_at ASC`).all();
  });

  app.post<{ Body: { name?: unknown } }>("/api/masters", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const name = request.body?.name;
    if (typeof name !== "string" || !name.trim()) {
      return reply.code(400).send({ error: "name is required" });
    }
    if (db.prepare(`SELECT 1 FROM masters WHERE name = ?`).get(name.trim())) {
      return reply.code(409).send({ error: "имя уже занято" });
    }

    const token = createMaster(db, name.trim());
    logMasterAction(db, master.id, "MASTER_CREATED", { name: name.trim() });
    return { name: name.trim(), token };
  });
}
