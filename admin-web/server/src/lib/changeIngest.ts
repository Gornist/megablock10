import type { Db } from "../db/index.js";
import { isField, isReason, signaturePayload, type ChangeRecordInput } from "./changeRecord.js";
import { verifySignature } from "./crypto.js";
import { ipv4Of, parseClientVersions, parseSyncState, peersSince, touchPresence } from "./presence.js";
import { RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX } from "./identityDefaults.js";
import { bindProvision } from "./provisions.js";

/**
 * Приём записей с устройств (то, что стоит за POST /api/changes), разложенный на шаги: разбор записи → статическая проверка →
 * привязка кода персонажа → вставка; отдельно — присутствие, подтверждения, ответ устройству. Сам маршрут (routes/changes.ts)
 * остаётся про HTTP: лимит, секрет игры, форма тела. Раньше всё это было одним замыканием на 190 строк.
 */

/** Дольше этого без heartbeat игрок не считается доступным для запасного обнаружения (телефон шлёт раз в ~30 с). */
const PEER_FRESH_MS = 90_000;

export const MAX_BATCH = 200;
/** Столько раз телефон может не применить правку мастера, прежде чем сервер перестанет её слать и покажет мастеру. */
export const MAX_APPLY_ATTEMPTS = 5;
const MAX_APPLY_ERROR_CHARS = 300;

export interface RejectedItem {
  id: string;
  error: string;
}

export interface PendingWire {
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

type Verdict = { ok: true } | { ok: false; error: string };

export function isChangeRecordInput(v: unknown): v is ChangeRecordInput {
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

const MAX_ID_CHARS = 100;
const MAX_REF_CHARS = 200;
const MAX_NAME_CHARS = 64;
const MAX_JSON_CHARS = 4096;
const INTEGER = /^-?\d{1,15}$/;

/**
 * Значение записи того вида, что ждёт свёртка (lib/projection.ts), — иначе запись попадала бы в историю и её тихо пропускала
 * бы свёртка. Баланс — целое (со знаком: мастер может увести в минус), RAM — целое 6..13, позывной и фракция — короткая строка
 * (пустая — при сбросе сессии), остальные поля — JSON-объект. Границы длины — чтобы одна запись не раздувала базу и дашборд.
 */
function valueProblem(r: ChangeRecordInput): string | null {
  if (r.id.length === 0 || r.id.length > MAX_ID_CHARS) return "bad id";
  if (r.sourceRef != null && r.sourceRef.length > MAX_REF_CHARS) return "sourceRef too long";
  const v = r.newValue ?? null;
  const old = r.oldValue ?? null;
  switch (r.field) {
    case "balance":
      if (v === null || !INTEGER.test(v)) return "balance must be an integer";
      if (old !== null && !INTEGER.test(old)) return "old balance must be an integer";
      return null;
    case "ramCapacity": {
      const n = v === null || !INTEGER.test(v) ? NaN : Number(v);
      if (!(n >= RAM_CAPACITY_DEFAULT && n <= RAM_CAPACITY_MAX)) return `ramCapacity must be an integer ${RAM_CAPACITY_DEFAULT}..${RAM_CAPACITY_MAX}`;
      return null;
    }
    case "callsign":
    case "faction":
      if (v === null || v.length > MAX_NAME_CHARS) return `${r.field} must be at most ${MAX_NAME_CHARS} chars`;
      return null;
    default: {
      if (v === null || v.length > MAX_JSON_CHARS) return `${r.field} must be a JSON object up to ${MAX_JSON_CHARS} chars`;
      try {
        const parsed: unknown = JSON.parse(v);
        if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return `${r.field} must be a JSON object`;
      } catch {
        return `${r.field} must be a JSON object`;
      }
      return null;
    }
  }
}

/** Проверки, не требующие БД: известные поле и причина, вид значения, автор, подпись. */
export function validateRecord(r: ChangeRecordInput): Verdict {
  if (!isField(r.field)) return { ok: false, error: `unknown field: ${r.field}` };
  if (!isReason(r.reason)) return { ok: false, error: `unknown reason: ${r.reason}` };
  // Правки мастера создаёт только сам сервер (routes/players.ts) — устройство, приславшее такую причину, подделывало бы запись «от мастера» в истории.
  if (r.reason === "MASTER_OVERRIDE") return { ok: false, error: "MASTER_OVERRIDE can only be issued by the collector" };
  const problem = valueProblem(r);
  if (problem) return { ok: false, error: problem };
  // subjectKeyB64 совпадает с отправителем, кроме TRANSFER_IN — там actor это контрагент (см. §3.1, §4).
  if (r.reason !== "TRANSFER_IN" && r.actor !== r.subjectKeyB64) return { ok: false, error: "actor must equal subjectKeyB64 for this reason" };
  const signer = r.reason === "TRANSFER_IN" ? r.subjectKeyB64 : r.actor;
  if (!verifySignature(signer, signaturePayload(r), r.signature)) return { ok: false, error: "invalid signature" };
  return { ok: true };
}

interface ExistingRow {
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
}

function sameRecord(e: ExistingRow, r: ChangeRecordInput): boolean {
  return (
    e.subject_key === r.subjectKeyB64 && e.seq === r.seq && e.happened_at === r.happenedAt && e.field === r.field &&
    e.old_value === (r.oldValue ?? null) && e.new_value === (r.newValue ?? null) && e.reason === r.reason &&
    e.source_ref === (r.sourceRef ?? null) && e.actor === r.actor && e.signature === r.signature
  );
}

export function createChangeIngest(db: Db) {
  const insertStmt = db.prepare(`
    INSERT INTO changes (id, subject_key, seq, happened_at, received_at, field, old_value, new_value, reason, source_ref, actor, signature)
    VALUES (@id, @subject_key, @seq, @happened_at, @received_at, @field, @old_value, @new_value, @reason, @source_ref, @actor, @signature)
  `);
  const existsBySeqStmt = db.prepare(`SELECT id FROM changes WHERE subject_key = ? AND seq = ?`);
  const byIdStmt = db.prepare(
    `SELECT subject_key, seq, happened_at, field, old_value, new_value, reason, source_ref, actor, signature FROM changes WHERE id = ?`,
  );
  const maxSeqStmt = db.prepare(`SELECT MAX(seq) AS maxSeq FROM changes WHERE subject_key = ?`);
  const pendingForSubjectStmt = db.prepare(`
    SELECT c.* FROM master_pending mp JOIN changes c ON c.id = mp.change_id
    WHERE mp.subject_key = ? AND mp.delivered = 0 AND mp.failed_at IS NULL
    ORDER BY c.seq ASC
  `);
  const subjectKnownStmt = db.prepare(`SELECT 1 FROM changes WHERE subject_key = ? LIMIT 1`);
  const markDeliveredStmt = db.prepare(
    `UPDATE master_pending SET delivered = 1, applied_at_seq = COALESCE(?, applied_at_seq) WHERE change_id = ? AND subject_key = ?`,
  );
  const markFailedStmt = db.prepare(`
    UPDATE master_pending
    SET attempts = attempts + 1, last_error = @error,
        failed_at = CASE WHEN @permanent = 1 OR attempts + 1 >= @max THEN @now ELSE NULL END
    WHERE change_id = @id AND subject_key = @subject AND delivered = 0 AND failed_at IS NULL
  `);

  const isKnown = (key: string) => subjectKnownStmt.get(key) !== undefined;

  /** Одна запись: разбор → повтор → статические проверки → уникальность seq → код персонажа → вставка. */
  function ingestOne(raw: unknown, receivedAt: number): { ok: true; id: string; subjectKeyB64: string } | { ok: false; id: string; error: string } {
    const idForError = typeof (raw as { id?: unknown })?.id === "string" ? (raw as { id: string }).id : "?";
    if (!isChangeRecordInput(raw)) return { ok: false, id: idForError, error: "malformed record" };
    const r = raw;

    // Повторная отправка той же записи — уже приняли, не ошибка (см. п.13: повтор не создаёт дублей). Но только ТОЙ ЖЕ: другая
    // запись с занятым id — конфликт, а не «принято» (иначе телефон удалил бы её из очереди, а сервер её так и не записал).
    const existing = byIdStmt.get(r.id) as ExistingRow | undefined;
    if (existing) {
      return sameRecord(existing, r)
        ? { ok: true, id: r.id, subjectKeyB64: r.subjectKeyB64 }
        : { ok: false, id: r.id, error: "id already used by a different record" };
    }

    const verdict = validateRecord(r);
    if (!verdict.ok) return { ok: false, id: r.id, error: verdict.error };
    if (existsBySeqStmt.get(r.subjectKeyB64, r.seq)) return { ok: false, id: r.id, error: "seq already used by a different record" };

    // Код персонажа (QR выдачи) одноразовый: первый телефон, приславший CHARACTER_CREATED с этим sourceRef, забирает его себе.
    if (r.reason === "CHARACTER_CREATED" && r.sourceRef) {
      const bound = bindProvision(db, r.sourceRef, r.subjectKeyB64, receivedAt);
      if (!bound.ok) return { ok: false, id: r.id, error: bound.error };
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

  // Одна транзакция на весь батч, не по одному autocommit-INSERT на запись (при MAX_BATCH=200 это раньше было 200 отдельных fsync).
  const insertBatchTx = db.transaction((records: unknown[], receivedAt: number) => {
    const accepted: string[] = [];
    const rejected: RejectedItem[] = [];
    const subjects = new Set<string>();
    for (const raw of records) {
      const result = ingestOne(raw, receivedAt);
      if (result.ok) {
        accepted.push(result.id);
        subjects.add(result.subjectKeyB64);
      } else {
        rejected.push({ id: result.id, error: result.error });
      }
    }
    return { accepted, rejected, subjects };
  });

  return {
    /**
     * heartbeat: игрок на связи, даже если писать в БД нечего. Адрес и порт для запасного обнаружения запоминаем только для известных
     * игроков (есть хоть одна запись) и только со своего адреса соединения — иначе любой в сети мог бы подсунуть чужой адрес.
     */
    touchPresence(subjectKey: string, rawPresence: unknown, ip: string | undefined) {
      const p = rawPresence as { chatPort?: unknown; callsign?: unknown; faction?: unknown; appVersion?: unknown; wireVersions?: unknown; pendingCount?: unknown; oldestPendingAgeMs?: unknown } | undefined;
      const host = ipv4Of(ip);
      const known = isKnown(subjectKey);
      const port = typeof p?.chatPort === "number" && Number.isInteger(p.chatPort) && p.chatPort > 0 && p.chatPort < 65536 ? p.chatPort : 0;
      touchPresence(
        subjectKey,
        Date.now(),
        known && host && port
          ? { host, port, callsign: typeof p?.callsign === "string" ? p.callsign.slice(0, 40) : "", faction: typeof p?.faction === "string" ? p.faction.slice(0, 40) : "" }
          : undefined,
        // версии — только известным игрокам, как и адрес: память не должна расти от чужих ключей
        known ? parseClientVersions(p?.appVersion, p?.wireVersions) : null,
        known ? parseSyncState(p?.pendingCount, p?.oldestPendingAgeMs) : null,
      );
    },

    /** Устройство подтверждает применённые правки мастера — только после этого они перестают доставляться (повтор безопасен: правки идемпотентны). */
    /**
     * Правки, которые устройство применило. [appliedAtSeq] — id → последний seq телефона в момент применения: по нему свёртка
     * ставит правку в хронологию устройства (старый клиент его не шлёт — тогда по времени прихода, как раньше).
     */
    acknowledge(subjectKey: string, ackIds: unknown[], appliedAtSeq: unknown = undefined) {
      const seqs = typeof appliedAtSeq === "object" && appliedAtSeq !== null ? (appliedAtSeq as Record<string, unknown>) : {};
      for (const id of ackIds.slice(0, MAX_BATCH)) {
        if (typeof id !== "string") continue;
        const seq = seqs[id];
        markDeliveredStmt.run(Number.isSafeInteger(seq) ? seq : null, id, subjectKey);
      }
    },

    /**
     * Правки, которые телефон не смог применить (вместо ackIds). Правка остаётся недоставленной и приходит снова; после
     * MAX_APPLY_ATTEMPTS отказов — или сразу, если телефон сообщил, что повтор бесполезен (поле, которого его версия не знает,
     * значение не того вида), — сервер перестаёт её слать (failed_at) и показывает мастеру (attentionRules, overrideFailed).
     */
    reportFailures(subjectKey: string, failures: unknown[], now: number) {
      for (const f of failures.slice(0, MAX_BATCH)) {
        if (typeof f !== "object" || f === null) continue;
        const { id, error, permanent } = f as { id?: unknown; error?: unknown; permanent?: unknown };
        if (typeof id !== "string") continue;
        const reason = typeof error === "string" && error.length > 0 ? error.slice(0, MAX_APPLY_ERROR_CHARS) : "без причины";
        markFailedStmt.run({ id, subject: subjectKey, error: reason, permanent: permanent === true ? 1 : 0, max: MAX_APPLY_ATTEMPTS, now });
      }
    },

    insertBatch(records: unknown[], receivedAt: number) {
      return insertBatchTx(records, receivedAt);
    },

    /** Для каждого затронутого игрока: последний известный серверу seq и накопленные правки мастера, ещё не подтверждённые устройством. */
    stateFor(subjects: Iterable<string>): { knownSeq: Record<string, number>; pending: PendingWire[] } {
      const knownSeq: Record<string, number> = {};
      const pending: PendingWire[] = [];
      for (const key of subjects) {
        knownSeq[key] = (maxSeqStmt.get(key) as { maxSeq: number | null }).maxSeq ?? 0;
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
      return { knownSeq, pending };
    },

    /**
     * Список адресов игроков — только тому, кого сервер уже знает (проверка ПОСЛЕ приёма батча: новичок, приславший первые записи
     * этим же запросом, уже известен). Иначе любой в сети, не имея ни одной записи, получал бы адреса, позывные и фракции всех.
     */
    peersFor(requester: unknown) {
      return typeof requester === "string" && isKnown(requester) ? peersSince(Date.now() - PEER_FRESH_MS, requester) : [];
    },
  };
}
