import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import fastifyStatic from "@fastify/static";
import { existsSync } from "node:fs";
import type { Db } from "./db/index.js";
import { registerChangesRoute } from "./routes/changes.js";
import { registerPlayersRoutes } from "./routes/players.js";
import { registerAuthRoute } from "./routes/auth.js";
import { registerContainersRoute } from "./routes/containers.js";
import { registerSlotsRoutes } from "./routes/slots.js";
import { registerNodesRoutes } from "./routes/nodes.js";
import { registerTransfersRoute } from "./routes/transfers.js";
import { registerOverviewRoutes } from "./routes/overview.js";
import { registerExportRoute } from "./routes/exportCsv.js";
import { registerMasterRoutes } from "./routes/master.js";
import { registerMastersRoutes } from "./routes/masters.js";
import { registerAuditRoute } from "./routes/audit.js";
import { registerAnnouncementsRoutes } from "./routes/announcements.js";
import { registerAnalyticsRoutes } from "./routes/analytics.js";
import { registerAttentionRoute } from "./routes/attention.js";
import { registerWatchRoutes } from "./routes/watch.js";
import { registerEventsRoute } from "./routes/events.js";
import { registerMetaRoute } from "./routes/meta.js";
import { registerPulseRoute } from "./routes/pulse.js";
import { registerProvisionRoutes } from "./routes/provisions.js";

/**
 * Собирает Fastify-приложение без побочного listen() — раньше вся сборка
 * жила прямо в index.ts вперемешку с app.listen(), из-за чего тесты не
 * могли получить app для app.inject() не открывая реальный порт. index.ts
 * теперь только вызывает buildApp() и слушает; тесты вызывают buildApp()
 * на in-memory БД (см. testDb.ts) и бьют через inject().
 */
export function buildApp(db: Db, options: { clientDist?: string; logger?: boolean } = {}): FastifyInstance {
  // Ключи персонажей — base64 EC SPKI DER (~124 символа) в URL-параметре,
  // после encodeURIComponent ещё длиннее — дефолтный лимит Fastify (100) в это
  // не помещается.
  const app = Fastify({ logger: options.logger ?? true, routerOptions: { maxParamLength: 512 } });

  // Без этого необработанное исключение (например, редкая ошибка better-sqlite3 не
  // отловленная валидацией заранее) долетало бы до клиента с err.message как есть —
  // Fastify по умолчанию не отдаёт стек-трейс в ответе, но message может содержать
  // детали БД (имя таблицы/колонки, кусок SQL). На /api/changes и /api/slots/:ref/claim
  // это разрешено правишь любому устройству в сети без авторизации мастера, поэтому
  // 5xx (неожиданная ошибка сервера) отдаём общей фразой, а исходную ошибку — в лог;
  // 4xx (уже свой statusCode — валидация самого Fastify, битый JSON и т. п.) message не прячем.
  app.setErrorHandler((error: FastifyError, request, reply) => {
    const statusCode = error.statusCode ?? 500;
    if (statusCode >= 500) {
      request.log.error(error);
      reply.code(statusCode).send({ error: "internal error" });
      return;
    }
    reply.code(statusCode).send({ error: error.message });
  });

  registerChangesRoute(app, db);
  registerPlayersRoutes(app, db);
  registerAuthRoute(app, db);
  registerContainersRoute(app, db);
  registerSlotsRoutes(app, db);
  registerNodesRoutes(app, db);
  registerTransfersRoute(app, db);
  registerOverviewRoutes(app, db);
  registerExportRoute(app, db);
  registerMasterRoutes(app, db);
  registerMastersRoutes(app, db);
  registerAuditRoute(app, db);
  registerAnnouncementsRoutes(app, db);
  registerAnalyticsRoutes(app, db);
  registerAttentionRoute(app, db);
  registerWatchRoutes(app, db);
  registerEventsRoute(app, db);
  registerMetaRoute(app, db);
  registerPulseRoute(app, db);
  registerProvisionRoutes(app, db);

  app.get("/api/health", async () => ({ ok: true }));

  // Раздача собранного фронта тем же процессом (§1 ТЗ — один процесс, без
  // Docker). В тестах clientDist не передаётся — фронт не собран и не нужен.
  if (options.clientDist && existsSync(options.clientDist)) {
    app.register(fastifyStatic, { root: options.clientDist });
    app.setNotFoundHandler((request, reply) => {
      if (request.raw.url?.startsWith("/api/")) return reply.code(404).send({ error: "not found" });
      return reply.sendFile("index.html");
    });
  } else if (options.clientDist) {
    app.log.warn(`client/dist не найден (${options.clientDist}) — фронт не раздаётся, только /api`);
  }

  return app;
}
