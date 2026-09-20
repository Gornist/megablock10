import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import {
  isField,
  isReason,
  signaturePayload,
  type ChangeRecordInput,
} from "../lib/changeRecord.js";
import { verifySignature } from "../lib/crypto.js";
import { checkGameSecret } from "../lib/gameSecret.js";
import { ipv4Of, peersSince, touchPresence } from "../lib/presence.js";

/** Дольше этого без heartbeat игрок не считается доступным для запасного обнаружения (телефон шлёт раз в ~30 с). */
const PEER_FRESH_MS = 90_000;

const MAX_BATCH = 200;

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
  /** Порт чат-сервера телефона и его позывной/фракция — для запасного обнаружения пиров (см. lib/presence.ts). Адрес сервер берёт сам, из соединения. */
  presence?: unknown;
}

interface RejectedItem {
  id: string;
  error: string;
}

interface PendingWire {
  id: string;
  subjectKeyB64: string;
  seq: number;
  happenedAt: number;
  field: string;
  oldValue: string | null;
  newValue: string | null;
  reason: string;
  sourceRef: string | null;
  actor: string;
  signature: string;
}

/**
 * POST /api/changes — приём батча ChangeRecord с устройств игроков (§3.1
 * ТЗ) и, тем же запросом, доставка накопленных MASTER_OVERRIDE обратно на
 * устройство (§6.3) — отдельного канала push нет, поэтому клиент опрашивает
 * этот же эндпоинт периодически, даже когда сам ничего не шлёт. Без
 * авторизации (её дёргают клиенты игроков в открытой игровой сети). Битая
 * запись отбрасывается в rejected, весь батч из-за неё не падает.
 */
export function registerChangesRoute(app: FastifyInstance, db: Db) {
  const insertStmt = db.prepare(`
    INSERT INTO changes (id, subject_key, seq, happened_at, received_at, field, old_value, new_value, reason, source_ref, actor, signature)
    VALUES (@id, @subject_key, @seq, @happened_at, @received_at, @field, @old_value, @new_value, @reason, @source_ref, @actor, @signature)
  `);
  const existsBySeqStmt = db.prepare(`SELECT id FROM changes WHERE subject_key = ? AND seq = ?`);
  const existsByIdStmt = db.prepare(`SELECT id FROM changes WHERE id = ?`);
  const maxSeqStmt = db.prepare(`SELECT MAX(seq) AS maxSeq FROM changes WHERE subject_key = ?`);
  const pendingForSubjectStmt = db.prepare(`
    SELECT c.* FROM master_pending mp JOIN changes c ON c.id = mp.change_id
    WHERE mp.subject_key = ? AND mp.delivered = 0
    ORDER BY c.seq ASC
  `);
  const subjectKnownStmt = db.prepare(`SELECT 1 FROM changes WHERE subject_key = ? LIMIT 1`);
  const markDeliveredStmt = db.prepare(`UPDATE master_pending SET delivered = 1 WHERE change_id = ? AND subject_key = ?`);

  app.post<{ Body: ChangesBody }>("/api/changes", async (request, reply) => {
    if (!checkGameSecret(request, reply)) return;

    const records = request.body?.records;
    if (!Array.isArray(records)) {
      return reply.code(400).send({ error: "records must be an array" });
    }
    if (records.length > MAX_BATCH) {
      return reply.code(400).send({ error: `batch too large, max ${MAX_BATCH}` });
    }

    const accepted: string[] = [];
    const rejected: RejectedItem[] = [];
    const touchedSubjects = new Set<string>();
    if (typeof request.body?.subjectKeyB64 === "string") {
      touchedSubjects.add(request.body.subjectKeyB64);
      // heartbeat: игрок на связи, даже если писать в БД нечего. Адрес и порт для запасного обнаружения запоминаем только для
      // известных игроков (есть хоть одна запись) и только со своего адреса соединения — иначе любой в сети мог бы подсунуть чужой адрес.
      const p = request.body.presence as { chatPort?: unknown; callsign?: unknown; faction?: unknown } | undefined;
      const host = ipv4Of(request.ip);
      const known = subjectKnownStmt.get(request.body.subjectKeyB64) !== undefined;
      const port = typeof p?.chatPort === "number" && Number.isInteger(p.chatPort) && p.chatPort > 0 && p.chatPort < 65536 ? p.chatPort : 0;
      touchPresence(
        request.body.subjectKeyB64,
        Date.now(),
        known && host && port
          ? { host, port, callsign: typeof p?.callsign === "string" ? p.callsign.slice(0, 40) : "", faction: typeof p?.faction === "string" ? p.faction.slice(0, 40) : "" }
          : undefined,
      );
    }

    const ackIds = request.body?.ackIds;
    if (typeof request.body?.subjectKeyB64 === "string" && Array.isArray(ackIds)) {
      const subject = request.body.subjectKeyB64;
      for (const id of ackIds.slice(0, MAX_BATCH)) {
        if (typeof id === "string") markDeliveredStmt.run(id, subject);
      }
    }

    const receivedAt = Date.now();

    // Одна транзакция на весь батч, не по одному autocommit-INSERT на запись
    // (при MAX_BATCH=200 это раньше было 200 отдельных fsync) — см.
    // routes/players.ts, applyOverride про тот же приём.
    const insertBatch = db.transaction((recs: unknown[]) => {
      for (const raw of recs) {
        const result = validateAndInsert(raw, receivedAt);
        if (result.ok) {
          accepted.push(result.id);
          touchedSubjects.add(result.subjectKeyB64);
        } else {
          rejected.push({ id: result.id, error: result.error });
        }
      }
    });
    insertBatch(records);

    const knownSeq: Record<string, number> = {};
    const pending: PendingWire[] = [];
    for (const key of touchedSubjects) {
      const row = maxSeqStmt.get(key) as { maxSeq: number | null };
      knownSeq[key] = row.maxSeq ?? 0;

      const rows = pendingForSubjectStmt.all(key) as {
        id: string;
        subject_key: string;
        seq: number;
        happened_at: number;
        field: string;
        old_value: string | null;
        new_value: string | null;
        reason: string;
        source_ref: string | null;
        actor: string;
        signature: string;
      }[];
      for (const row of rows) {
        pending.push({
          id: row.id,
          subjectKeyB64: row.subject_key,
          seq: row.seq,
          happenedAt: row.happened_at,
          field: row.field,
          oldValue: row.old_value,
          newValue: row.new_value,
          reason: row.reason,
          sourceRef: row.source_ref,
          actor: row.actor,
          signature: row.signature,
        });
      }
    }

    const peers = typeof request.body?.subjectKeyB64 === "string" ? peersSince(Date.now() - PEER_FRESH_MS, request.body.subjectKeyB64) : [];
    return { accepted, rejected, knownSeq, pending, peers };

    function validateAndInsert(
      raw: unknown,
      receivedAt: number,
    ): { ok: true; id: string; subjectKeyB64: string } | { ok: false; id: string; error: string } {
      const idForError = typeof (raw as { id?: unknown })?.id === "string" ? (raw as { id: string }).id : "?";

      if (!isChangeRecordInput(raw)) {
        return { ok: false, id: idForError, error: "malformed record" };
      }
      const r: ChangeRecordInput = raw;

      if (existsByIdStmt.get(r.id)) {
        // Повторная отправка того же id — уже приняли, не ошибка (см. п.13: повтор не создаёт дублей).
        return { ok: true, id: r.id, subjectKeyB64: r.subjectKeyB64 };
      }
      if (!isField(r.field)) {
        return { ok: false, id: r.id, error: `unknown field: ${r.field}` };
      }
      if (!isReason(r.reason)) {
        return { ok: false, id: r.id, error: `unknown reason: ${r.reason}` };
      }
      // Правки мастера создаёт только сам сервер (routes/players.ts) — устройство,
      // приславшее такую причину, подделывало бы запись "от мастера" в истории.
      if (r.reason === "MASTER_OVERRIDE") {
        return { ok: false, id: r.id, error: "MASTER_OVERRIDE can only be issued by the collector" };
      }
      // subjectKeyB64 совпадает с отправителем, кроме TRANSFER_IN — там actor это контрагент (см. §3.1, §4).
      if (r.reason !== "TRANSFER_IN" && r.actor !== r.subjectKeyB64) {
        return { ok: false, id: r.id, error: "actor must equal subjectKeyB64 for this reason" };
      }
      const signer = r.reason === "TRANSFER_IN" ? r.subjectKeyB64 : r.actor;
      if (!verifySignature(signer, signaturePayload(r), r.signature)) {
        return { ok: false, id: r.id, error: "invalid signature" };
      }
      if (existsBySeqStmt.get(r.subjectKeyB64, r.seq)) {
        return { ok: false, id: r.id, error: "seq already used by a different record" };
      }

      insertStmt.run({
        id: r.id,
        subject_key: r.subjectKeyB64,
        seq: r.seq,
        happened_at: r.happenedAt,
        received_at: receivedAt,
        field: r.field,
        old_value: r.oldValue ?? null,
        new_value: r.newValue ?? null,
        reason: r.reason,
        source_ref: r.sourceRef ?? null,
        actor: r.actor,
        signature: r.signature,
      });

      return { ok: true, id: r.id, subjectKeyB64: r.subjectKeyB64 };
    }
  });
}

function isChangeRecordInput(v: unknown): v is ChangeRecordInput {
  if (typeof v !== "object" || v === null) return false;
  const r = v as Record<string, unknown>;
  return (
    typeof r.id === "string" &&
    typeof r.subjectKeyB64 === "string" &&
    typeof r.seq === "number" &&
    Number.isInteger(r.seq) &&
    typeof r.happenedAt === "number" &&
    typeof r.field === "string" &&
    (r.oldValue === null || r.oldValue === undefined || typeof r.oldValue === "string") &&
    (r.newValue === null || r.newValue === undefined || typeof r.newValue === "string") &&
    typeof r.reason === "string" &&
    (r.sourceRef === undefined || r.sourceRef === null || typeof r.sourceRef === "string") &&
    typeof r.actor === "string" &&
    typeof r.signature === "string"
  );
}
