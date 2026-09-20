import type { FastifyInstance } from "fastify";
import type { Meta } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { REASONS } from "../lib/changeRecord.js";
import { KIND_LABEL_RU } from "../lib/eventKinds.js";
import { REASON_LABEL_RU } from "../lib/humanize.js";

/**
 * GET /api/meta — справочники для фильтров и подписей: причины событий и типы.
 * Раньше эти списки жили ещё и на клиенте (reasons.ts, константы экранов) и
 * расходились при добавлении новой причины; теперь единственный источник — сервер.
 */
export function registerMetaRoute(app: FastifyInstance, db: Db) {
  app.get("/api/meta", async (request, reply): Promise<Meta | void> => {
    if (!requireMaster(db, request, reply)) return;
    return {
      reasons: REASONS.map((code) => ({ code, label: REASON_LABEL_RU[code] ?? code })),
      kinds: Object.entries(KIND_LABEL_RU).map(([code, label]) => ({ code, label })),
    };
  });
}
