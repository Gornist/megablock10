import { withHuman } from "../lib/humanize.js";
import { lastPresence } from "../lib/presence.js";
import type { FastifyInstance } from "fastify";
import { escapeLike } from "../lib/sqlLike.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { projectCharacter } from "../lib/projection.js";
import { cachedByDbVersion } from "../lib/dbCache.js";
import { randomUUID } from "node:crypto";
import type { Field } from "../lib/changeRecord.js";

const ONLINE_WINDOW_MS = 5 * 60 * 1000;
/** Только скалярные поля персонажа — правка daemons.add/shards.add/counters.* через дашборд не предусмотрена (нет формы, нет смысла: это коллекции, не значения). */
const OVERRIDABLE_FIELDS: Field[] = ["balance", "ramCapacity", "callsign", "faction"];

type PlayerBase = ReturnType<typeof computePlayerBase>[number];

/** Всё, что зависит только от БД (кэшируемо по dbCache.ts) — без online, он зависит от текущего времени, не только от записей. */
function computePlayerBase(db: Db) {
  const keys = (db.prepare(`SELECT DISTINCT subject_key FROM changes`).all() as { subject_key: string }[]).map((r) => r.subject_key);
  return keys
    .map((key) => projectCharacter(db, key))
    .filter((s): s is NonNullable<typeof s> => s !== null)
    .map((s) => ({
      publicKeyB64: s.publicKeyB64,
      callsign: s.callsign,
      faction: s.faction,
      ramCapacity: s.ramCapacity,
      balance: s.balance,
      daemonCount: s.daemons.length,
      shardsByTier: countByTier(s.shards.map((sh) => sh.tier)),
      breaches: sumBreaches(s.counters.breaches),
      slotsClaimed: s.counters.slotsClaimed,
      lastSeenAt: s.lastSeenAt,
    }));
}

function withOnline(base: PlayerBase[]) {
  const now = Date.now();
  return base.map((s) => {
    const seenAt = Math.max(s.lastSeenAt, lastPresence(s.publicKeyB64)); // запись изменения ИЛИ heartbeat телефона
    return { ...s, lastSeenAt: seenAt, online: now - seenAt < ONLINE_WINDOW_MS };
  });
}

/** Переиспользуется CSV-экспортом (routes/exportCsv.ts) — простая некэшированная версия, годится и для нечастых вызовов, и для тестов. */
export function listPlayerSummaries(db: Db) {
  return withOnline(computePlayerBase(db));
}

/** GET /api/players/:key, /api/players, /api/players/:key/history, POST /api/players/:key/override — §7, §8.2, §8.3 ТЗ. */
export function registerPlayersRoutes(app: FastifyInstance, db: Db) {
  // Кэш только на "тяжёлую" часть (перебор истории всех игроков) — online
  // считается заново на каждый запрос из свежего Date.now(), иначе игрок,
  // переставший слать реальные события (но не сам факт связи — heartbeat
  // пустыми батчами ничего не пишет в БД), завис бы "в сети" навечно между
  // записями. См. dbCache.ts про то, почему кэш вообще по версии БД, а не по TTL.
  const cachedPlayerBase = cachedByDbVersion(db, () => computePlayerBase(db));

  app.get("/api/players", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    return withOnline(cachedPlayerBase());
  });

  app.get<{ Params: { key: string } }>("/api/players/:key", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const snapshot = projectCharacter(db, request.params.key);
    if (!snapshot) return reply.code(404).send({ error: "unknown character" });
    return snapshot;
  });

  app.get<{
    Params: { key: string };
    Querystring: { reason?: string; field?: string; source?: string; page?: string; pageSize?: string };
  }>("/api/players/:key/history", async (request, reply) => {
      if (!requireMaster(db, request, reply)) return;

      const pageSize = Math.min(200, Math.max(1, Number(request.query.pageSize) || 50));
      const page = Math.max(0, Number(request.query.page) || 0);

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

  /** POST /api/players/:key/override — ручная правка мастера (§6, §7). reason=MASTER_OVERRIDE, sourceRef = обязательное основание. */
  app.post<{
    Params: { key: string };
    Body: { field?: unknown; newValue?: unknown; reason?: unknown };
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
    // Значение должно быть таким, которое телефон реально применит: иначе на дашборде оно
    // отображается (NaN, пустой позывной), а устройство молча его игнорирует — расхождение навсегда.
    if (field === "balance" && !/^-?\d+$/.test(newValue)) {
      return reply.code(400).send({ error: "balance must be an integer" });
    }
    if (field === "ramCapacity" && !(/^\d+$/.test(newValue) && Number(newValue) >= 6 && Number(newValue) <= 13)) {
      return reply.code(400).send({ error: "ramCapacity must be an integer from 6 to 13" });
    }
    if ((field === "callsign" || field === "faction") && newValue.trim() === "") {
      return reply.code(400).send({ error: `${field} must not be empty` });
    }

    const subjectKey = request.params.key;
    const current = projectCharacter(db, subjectKey);
    const oldValue = current ? currentFieldValue(current, field as Field) : null;

    const id = randomUUID();
    const now = Date.now();

    // Запись в changes и постановка в очередь доставки на устройство — одной
    // транзакцией, чтобы либо и то, и другое, либо ничего (иначе возможна
    // правка, которая видна в истории на дашборде, но никогда не долетит
    // до игрока, если процесс упадёт между двумя INSERT).
    const applyOverride = db.transaction(() => {
      // seq мастерских правок — ОТДЕЛЬНЫЙ отрицательный диапазон, не
      // "следующий после устройства". Устройство нумерует seq САМО и
      // независимо от сервера (IdentityManager.nextChangeSeq, offline-first —
      // см. §3.4 ТЗ); если бы мы брали MAX(seq)+1 здесь, эта же цифра рано
      // или поздно совпала бы с seq, которую устройство присвоит одному из
      // СВОИХ будущих событий — и то, и другое не может лечь в таблицу
      // разом из-за UNIQUE(subject_key, seq): свежая законная запись игрока
      // получила бы "seq already used" и потерялась бы молча. Отрицательные
      // числа гарантированно никогда не встретятся у устройства (его
      // счётчик стартует с 1 и только растёт) — коллизия отсюда структурно
      // невозможна, а не просто маловероятна. Порядок применения при этом
      // берётся не из seq (см. projection.ts), а из received_at.
      const minSeqRow = db.prepare(`SELECT MIN(seq) AS minSeq FROM changes WHERE subject_key = ?`).get(subjectKey) as {
        minSeq: number | null;
      };
      const seq = Math.min(0, minSeqRow.minSeq ?? 0) - 1;

      db.prepare(
        `INSERT INTO changes (id, subject_key, seq, happened_at, received_at, field, old_value, new_value, reason, source_ref, actor, signature)
         VALUES (@id, @subject_key, @seq, @happened_at, @received_at, @field, @old_value, @new_value, @reason, @source_ref, @actor, @signature)`,
      ).run({
        id,
        subject_key: subjectKey,
        seq,
        happened_at: now,
        received_at: now,
        field,
        old_value: oldValue,
        new_value: newValue,
        reason: "MASTER_OVERRIDE",
        source_ref: justification,
        actor: `master:${master.id}`,
        signature: "",
      });

      db.prepare(`INSERT INTO master_pending (change_id, subject_key, delivered, created_at) VALUES (?, ?, 0, ?)`).run(id, subjectKey, now);

      return seq;
    });
    const seq = applyOverride();

    logMasterAction(db, master.id, "PLAYER_OVERRIDE", { subjectKey, field, oldValue, newValue, justification });

    return { id, seq };
  });
}

function currentFieldValue(snapshot: ReturnType<typeof projectCharacter>, field: Field): string | null {
  if (!snapshot) return null;
  switch (field) {
    case "balance":
      return String(snapshot.balance);
    case "ramCapacity":
      return String(snapshot.ramCapacity);
    case "callsign":
      return snapshot.callsign;
    case "faction":
      return snapshot.faction;
    default:
      return null;
  }
}

function countByTier(tiers: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const t of tiers) out[t] = (out[t] ?? 0) + 1;
  return out;
}

function sumBreaches(breaches: Record<string, { success: number; partial: number; fail: number }>) {
  let success = 0,
    partial = 0,
    fail = 0;
  for (const b of Object.values(breaches)) {
    success += b.success;
    partial += b.partial;
    fail += b.fail;
  }
  return { success, partial, fail };
}
