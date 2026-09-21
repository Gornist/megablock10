import { withHuman } from "../lib/humanize.js";
import { parsePaging } from "../lib/paging.js";
import type { FastifyInstance } from "fastify";
import { escapeLike } from "../lib/sqlLike.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { projectCharacter } from "../lib/projection.js";
import type { Field } from "../lib/changeRecord.js";
import { replacedMap, replacesMap } from "../lib/provisions.js";
import { computePlayerBase, getPlayerBase, withOnline } from "../lib/playerSummary.js";
import {
  BULK_FIELDS,
  OVERRIDABLE_FIELDS,
  currentFieldValue,
  insertMasterRecords,
  resolveValue,
  selectTargets,
  type OverrideMode,
  type TargetSelectorInput,
} from "../lib/masterRecords.js";

/** ?until=<мс> — «состояние на момент T»; пусто/некорректно → текущее. */
function parseUntil(raw: unknown): number | undefined {
  if (raw === undefined || raw === "") return undefined;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}

function parseMode(raw: unknown): OverrideMode | null {
  if (raw === undefined) return "set";
  return raw === "set" || raw === "add" ? raw : null;
}

/** Переиспользуется CSV-экспортом (routes/exportCsv.ts) — простая некэшированная версия, годится и для нечастых вызовов, и для тестов. */
export function listPlayerSummaries(db: Db) {
  return withOnline(computePlayerBase(db));
}

/** GET /api/players/:key, /api/players, /api/players/:key/history, POST /api/players/:key/override — §7, §8.2, §8.3 ТЗ. */
export function registerPlayersRoutes(app: FastifyInstance, db: Db) {
  // Кэш только на "тяжёлую" часть (перебор истории всех игроков, см.
  // getPlayerBase) — online считается заново на каждый запрос из свежего
  // Date.now(), иначе игрок, переставший слать реальные события (но не сам
  // факт связи — heartbeat пустыми батчами ничего не пишет в БД), завис бы
  // "в сети" навечно между записями. См. dbCache.ts про то, почему кэш вообще
  // по версии БД, а не по TTL.
  app.get<{ Querystring: { until?: string } }>("/api/players", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const until = parseUntil(request.query.until);
    // «На момент T» — история, не текущая связь: online там не определён, кэш обходим.
    if (until !== undefined) return computePlayerBase(db, until).map((p) => ({ ...p, online: false }));
    return withOnline(getPlayerBase(db));
  });

  app.get<{ Params: { key: string }; Querystring: { until?: string } }>("/api/players/:key", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const snapshot = projectCharacter(db, request.params.key, parseUntil(request.query.until));
    if (!snapshot) return reply.code(404).send({ error: "unknown character" });
    return { ...snapshot, replacedBy: replacedMap(db).get(snapshot.publicKeyB64) ?? null, replaces: replacesMap(db).get(snapshot.publicKeyB64) ?? null };
  });

  app.get<{
    Params: { key: string };
    Querystring: { reason?: string; field?: string; source?: string; page?: string; pageSize?: string };
  }>("/api/players/:key/history", async (request, reply) => {
      if (!requireMaster(db, request, reply)) return;

      const { page, pageSize } = parsePaging(request.query);

      const clauses = ["subject_key = ?"];
      const params: unknown[] = [request.params.key];
      if (request.query.reason) {
        clauses.push("reason = ?");
        params.push(request.query.reason);
      }
      if (request.query.field) {
        clauses.push("field = ?");
        params.push(request.query.field);
      }
      if (request.query.source) {
        // Подстрока, не точное совпадение — «покажи всё, что вышло из узла nasos-4» (§8.3 ТЗ) ищет по префиксу/куску source_ref.
        clauses.push("source_ref LIKE ? ESCAPE '\\'");
        params.push(`%${escapeLike(request.query.source)}%`);
      }
      const where = clauses.join(" AND ");

      const total = (db.prepare(`SELECT COUNT(*) AS n FROM changes WHERE ${where}`).get(...params) as { n: number }).n;
      const rows = db
        .prepare(`SELECT * FROM changes WHERE ${where} ORDER BY seq DESC LIMIT ? OFFSET ?`)
        .all(...params, pageSize, page * pageSize);

      return { total, page, pageSize, records: withHuman(db, rows as never[]) };
    },
  );

  /**
   * POST /api/players/:key/override — ручная правка мастера (§6, §7).
   * reason=MASTER_OVERRIDE, sourceRef = обязательное основание. mode="add" —
   * дельта к текущему значению (только balance/ramCapacity), по умолчанию "set".
   */
  app.post<{
    Params: { key: string };
    Body: { field?: unknown; newValue?: unknown; reason?: unknown; mode?: unknown };
  }>("/api/players/:key/override", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const { field, newValue, reason: justification } = request.body ?? {};
    if (typeof field !== "string" || typeof justification !== "string" || justification.trim() === "") {
      return reply.code(400).send({ error: "field and a non-empty justification (reason) are required" });
    }
    if (!OVERRIDABLE_FIELDS.includes(field as Field)) {
      return reply.code(400).send({ error: `field must be one of: ${OVERRIDABLE_FIELDS.join(", ")}` });
    }
    if (typeof newValue !== "string") {
      return reply.code(400).send({ error: "newValue must be a string" });
    }
    const mode = parseMode(request.body?.mode);
    if (!mode) return reply.code(400).send({ error: "mode must be set or add" });

    const subjectKey = request.params.key;
    const current = projectCharacter(db, subjectKey);
    const resolved = resolveValue(field as Field, mode, newValue, current);
    if (!resolved.ok) return reply.code(400).send({ error: resolved.error });
    const oldValue = currentFieldValue(current, field as Field);

    const [record] = insertMasterRecords(db, master.id, [
      { subjectKey, field, oldValue, newValue: resolved.value, sourceRef: justification },
    ]);

    logMasterAction(db, master.id, "PLAYER_OVERRIDE", { subjectKey, field, mode, oldValue, newValue: resolved.value, justification });

    return { id: record.id, seq: record.seq };
  });

  /**
   * POST /api/players/bulk-override — та же правка сразу многим: выбранным,
   * целой фракции или всем. dryRun=true — только предпросмотр («кому что
   * изменится»), ничего не пишет: массовая ошибка на 100 игроков дороже
   * одиночной, поэтому UI всегда сначала показывает предпросмотр.
   */
  app.post<{
    Body: TargetSelectorInput & { field?: unknown; newValue?: unknown; reason?: unknown; mode?: unknown; dryRun?: unknown };
  }>("/api/players/bulk-override", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const body = request.body ?? {};
    const { field, newValue, reason: justification } = body;
    if (typeof field !== "string" || typeof justification !== "string" || justification.trim() === "") {
      return reply.code(400).send({ error: "field and a non-empty justification (reason) are required" });
    }
    if (!BULK_FIELDS.includes(field as Field)) {
      return reply.code(400).send({ error: `field must be one of: ${BULK_FIELDS.join(", ")}` });
    }
    if (typeof newValue !== "string") return reply.code(400).send({ error: "newValue must be a string" });
    const mode = parseMode(body.mode);
    if (!mode) return reply.code(400).send({ error: "mode must be set or add" });

    const targets = selectTargets(getPlayerBase(db), body);
    if (!targets.ok) return reply.code(400).send({ error: targets.error });

    const plan: { publicKeyB64: string; callsign: string; oldValue: string | null; newValue: string }[] = [];
    for (const p of targets.players) {
      const resolved = resolveValue(field as Field, mode, newValue, p);
      if (!resolved.ok) return reply.code(400).send({ error: resolved.error });
      plan.push({
        publicKeyB64: p.publicKeyB64,
        callsign: p.callsign,
        oldValue: currentFieldValue(p, field as Field),
        newValue: resolved.value,
      });
    }
    // Значение не изменится (тот же баланс, RAM уже на потолке) — писать пустую правку игроку незачем.
    const changes = plan.filter((c) => c.oldValue !== c.newValue);

    if (body.dryRun === true) {
      return { dryRun: true, target: targets.label, count: changes.length, unchanged: plan.length - changes.length, changes };
    }
    if (changes.length === 0) return reply.code(400).send({ error: "no players would change" });

    const records = insertMasterRecords(
      db,
      master.id,
      changes.map((c) => ({ subjectKey: c.publicKeyB64, field, oldValue: c.oldValue, newValue: c.newValue, sourceRef: justification })),
    );
    logMasterAction(db, master.id, "BULK_OVERRIDE", {
      field,
      mode,
      newValue,
      justification,
      target: targets.label,
      count: records.length,
      keys: changes.map((c) => c.publicKeyB64),
    });
    return { dryRun: false, target: targets.label, count: records.length, unchanged: plan.length - changes.length };
  });
}
