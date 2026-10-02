import type { FastifyInstance } from "fastify";
import { RateLimiter } from "../lib/rateLimit.js";

/**
 * Что коллектор понимает из «Сети» (docs/netrun-world-records.md, раздел 5, п. 5). Мост читает это ДО отправки: kit после ответа
 * `rejected` удаляет запись из очереди, и запись, которую коллектор не знает, теряется молча — поэтому без признака Мост писать
 * записи мира не начинает. Версии — целые, растут при несовместимом изменении формата; 0 или отсутствие — «не понимаю».
 */
export const CAPABILITIES = {
  /** net.run / net.item / net.alert и причины NET_* принимаются приёмом /api/changes. */
  world_records: 1,
  /** POST /api/world-events (быстрые события на точки) — включается вместе с самим эндпоинтом. */
  world_events: 0,
} as const;

/**
 * GET /api/capabilities — открытый, без сессии мастера и секрета игры: в ответе только номера версий. Лимит — как у /api/changes,
 * чтобы зациклившийся клиент не занял единственный поток сервера.
 */
export function registerCapabilitiesRoute(app: FastifyInstance) {
  const perMinute = Number(process.env.CHANGES_RATE_PER_MIN ?? 120);
  const limiter = perMinute > 0 ? new RateLimiter(perMinute, 60_000) : null;
  app.get("/api/capabilities", async (request, reply) => {
    if (limiter?.hit(request.ip)) {
      reply.header("retry-after", "30");
      return reply.code(429).send({ error: "too many requests" });
    }
    return CAPABILITIES;
  });
}
