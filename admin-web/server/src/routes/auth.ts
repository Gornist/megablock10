import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { login, logout } from "../lib/auth.js";
import { RateLimiter } from "../lib/rateLimit.js";

interface LoginBody {
  name?: unknown;
  token?: unknown;
}

/** POST /api/auth/login — форма входа мастера, см. §9 ТЗ. Выдаёт сессионный токен на сутки; сам предвыданный токен мастера нигде, кроме БД (хэшем), не хранится. */
export function registerAuthRoute(app: FastifyInstance, db: Db) {
  // Внутри функции, не на уровне модуля — иначе все buildApp() в одном
  // процессе (в проде их и правда одна, но не в тестах, где на файл может
  // приходиться несколько app с разными БД) делили бы один и тот же счётчик.
  const loginLimiter = new RateLimiter(10, 5 * 60 * 1000);

  app.post<{ Body: LoginBody }>("/api/auth/login", async (request, reply) => {
    // Дашборд в открытой игровой сети (§9) — без лимита перебор мастерского токена ничем не ограничен.
    if (loginLimiter.hit(request.ip)) {
      return reply.code(429).send({ error: "слишком много попыток входа, попробуйте позже" });
    }

    const { name, token } = request.body ?? {};
    if (typeof name !== "string" || typeof token !== "string") {
      return reply.code(400).send({ error: "name and token are required" });
    }
    const result = login(db, name, token);
    if (!result) return reply.code(401).send({ error: "invalid credentials" });

    loginLimiter.reset(request.ip);
    return { sessionToken: result.sessionToken, master: result.master, expiresAt: result.expiresAt };
  });

  /** POST /api/auth/logout — закрыть сессию на сервере. Всегда 200: недействительный токен — то же самое, что «уже вышел». */
  app.post("/api/auth/logout", async (request) => {
    logout(db, request);
    return { ok: true };
  });
}
