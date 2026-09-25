import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { MAX_BATCH, createChangeIngest } from "../lib/changeIngest.js";
import { checkGameSecret } from "../lib/gameSecret.js";
import { pulse } from "../lib/pulse.js";
import { RateLimiter } from "../lib/rateLimit.js";

interface ChangesBody {
  records?: unknown;
  /** Не входит в состав ни одной записи — нужен, чтобы устройство могло спросить "есть что доставить?" даже пустым батчем (см. §6.3, ChangeRecordStore.kt на клиенте опрашивает раз в 30с и когда нечего слать). */
  subjectKeyB64?: unknown;
  /**
   * id правок мастера (MASTER_OVERRIDE), которые устройство уже применило —
   * только после этого они перестают доставляться. Раньше запись помечалась
   * доставленной в момент формирования ответа: потерянный ответ (обрыв
   * сети) или сбой при применении на устройстве навсегда терял правку.
   * Повторная доставка безопасна — все правки применяются идемпотентно.
   */
  ackIds?: unknown;
  /** id подтверждённой правки → последний seq устройства в момент её применения (см. lib/projection.ts). */
  appliedAtSeq?: unknown;
  /** Правки мастера, которые устройство применить не смогло: [{ id, error, permanent }] — вместо ack (см. lib/changeIngest.ts, reportFailures). */
  failures?: unknown;
  /** Порт чат-сервера телефона и его позывной/фракция — для запасного обнаружения пиров (см. lib/presence.ts). Адрес сервер берёт сам, из соединения. */
  presence?: unknown;
}

/**
 * POST /api/changes — приём батча ChangeRecord с устройств игроков (§3.1
 * ТЗ) и, тем же запросом, доставка накопленных MASTER_OVERRIDE обратно на
 * устройство (§6.3) — отдельного канала push нет, поэтому клиент опрашивает
 * этот же эндпоинт периодически, даже когда сам ничего не шлёт. Без
 * авторизации (её дёргают клиенты игроков в открытой игровой сети). Битая
 * запись отбрасывается в rejected, весь батч из-за неё не падает.
 * Разбор и приём записей — lib/changeIngest.ts; здесь только HTTP: лимит, секрет игры, форма тела, ответ.
 */
export function registerChangesRoute(app: FastifyInstance, db: Db) {
  const ingest = createChangeIngest(db);

  // Открытый для всех устройств эндпоинт (игроки без авторизации): без лимита один зациклившийся или враждебный клиент в
  // сети мог занять единственный поток сервера. Нормальный телефон шлёт ~2 запроса в минуту (heartbeat + ack), пачки по 200
  // записей идут подряд, но их единицы — 120/мин на адрес с запасом; CHANGES_RATE_PER_MIN=0 отключает лимит.
  const perMinute = Number(process.env.CHANGES_RATE_PER_MIN ?? 120);
  const limiter = perMinute > 0 ? new RateLimiter(perMinute, 60_000) : null;

  // Задержка приёма — метрика пульса (сервер однопоточный: рост задержки = перегрузка).
  app.addHook("onResponse", async (request, reply) => {
    if (request.method === "POST" && request.routeOptions.url === "/api/changes") pulse.request(reply.elapsedTime);
  });

  app.post<{ Body: ChangesBody }>("/api/changes", async (request, reply) => {
    if (limiter?.hit(request.ip)) {
      pulse.rateLimited();
      reply.header("retry-after", "30");
      return reply.code(429).send({ error: "too many requests" });
    }
    if (!checkGameSecret(request, reply)) {
      pulse.secretDenied();
      return;
    }

    const body = request.body ?? {};
    const records = body.records;
    if (!Array.isArray(records)) return reply.code(400).send({ error: "records must be an array" });
    if (records.length > MAX_BATCH) return reply.code(400).send({ error: `batch too large, max ${MAX_BATCH}` });

    const subject = typeof body.subjectKeyB64 === "string" ? body.subjectKeyB64 : null;
    if (subject) {
      pulse.heartbeat();
      ingest.touchPresence(subject, body.presence, request.ip);
      if (Array.isArray(body.ackIds)) ingest.acknowledge(subject, body.ackIds, body.appliedAtSeq);
      if (Array.isArray(body.failures)) ingest.reportFailures(subject, body.failures, Date.now());
    }

    const { accepted, rejected, subjects } = ingest.insertBatch(records, Date.now());
    pulse.batch(accepted.length, rejected.map((r) => r.error));

    // Сначала сам опрашивающий (как и раньше), затем авторы принятых записей.
    const touched = new Set<string>(subject ? [subject] : []);
    for (const key of subjects) touched.add(key);
    const { knownSeq, pending } = ingest.stateFor(touched);
    return { accepted, rejected, knownSeq, pending, peers: ingest.peersFor(subject) };
  });
}
