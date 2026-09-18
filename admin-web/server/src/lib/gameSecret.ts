import { timingSafeEqual } from "node:crypto";
import type { FastifyReply, FastifyRequest } from "fastify";

/**
 * Необязательный общий "секрет игры" для /api/changes и /api/slots/:ref/claim
 * — двух эндпоинтов, куда стучится любое устройство игрока без авторизации
 * мастера. Подлинность конкретной записи и так гарантирует подпись ECDSA
 * (её тут не заменяет), но подпись не мешает случайному устройству в той же
 * Wi-Fi-сети на игре просто бомбить эндпоинт мусором. Если GAME_SECRET не
 * задан в окружении — проверка выключена целиком (как было раньше), чтобы
 * не ломать локальную разработку и тесты, где секрет никто не настраивал.
 */
export function checkGameSecret(request: FastifyRequest, reply: FastifyReply): boolean {
  const expected = process.env.GAME_SECRET;
  if (!expected) return true;

  const provided = request.headers["x-game-secret"];
  if (typeof provided !== "string" || !timingSafeEqualStrings(provided, expected)) {
    reply.code(401).send({ error: "invalid or missing X-Game-Secret" });
    return false;
  }
  return true;
}

function timingSafeEqualStrings(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  return bufA.length === bufB.length && timingSafeEqual(bufA, bufB);
}
