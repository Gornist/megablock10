import type { Db } from "../db/index.js";
import { isField, isReason, signaturePayload, type ChangeRecordInput } from "./changeRecord.js";
import { verifySignature } from "./crypto.js";
import { ipv4Of, parseClientVersions, peersSince, touchPresence } from "./presence.js";
import { bindProvision } from "./provisions.js";

/**
 * Приём записей с устройств (то, что стоит за POST /api/changes), разложенный на шаги: разбор записи → статическая проверка →
 * привязка кода персонажа → вставка; отдельно — присутствие, подтверждения, ответ устройству. Сам маршрут (routes/changes.ts)
 * остаётся про HTTP: лимит, секрет игры, форма тела. Раньше всё это было одним замыканием на 190 строк.
 */

/** Дольше этого без heartbeat игрок не считается доступным для запасного обнаружения (телефон шлёт раз в ~30 с). */
const PEER_FRESH_MS = 90_000;

export const MAX_BATCH = 200;

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

/** Проверки, не требующие БД: известные поле и причина, автор, подпись. */
export function validateRecord(r: ChangeRecordInput): Verdict {
  if (!isField(r.field)) return { ok: false, error: `unknown field: ${r.field}` };
  if (!isReason(r.reason)) return { ok: false, error: `unknown reason: ${r.reason}` };
  // Правки мастера создаёт только сам сервер (routes/players.ts) — устройство, приславшее такую причину, подделывало бы запись «от мастера» в истории.
  if (r.reason === "MASTER_OVERRIDE") return { ok: false, error: "MASTER_OVERRIDE can only be issued by the collector" };
  // subjectKeyB64 совпадает с отправителем, кроме TRANSFER_IN — там actor это контрагент (см. §3.1, §4).
  if (r.reason !== "TRANSFER_IN" && r.actor !== r.subjectKeyB64) return { ok: false, error: "actor must equal subjectKeyB64 for this reason" };
  const signer = r.reason === "TRANSFER_IN" ? r.subjectKeyB64 : r.actor;
  if (!verifySignature(signer, signaturePayload(r), r.signature)) return { ok: false, error: "invalid signature" };
  return { ok: true };
}

export function createChangeIngest(db: Db) {
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

  const isKnown = (key: string) => subjectKnownStmt.get(key) !== undefined;

  /** Одна запись: разбор → повтор → статические проверки → уникальность seq → код персонажа → вставка. */
  function ingestOne(raw: unknown, receivedAt: number): { ok: true; id: string; subjectKeyB64: string } | { ok: false; id: string; error: string } {
    const idForError = typeof (raw as { id?: unknown })?.id === "string" ? (raw as { id: string }).id : "?";
    if (!isChangeRecordInput(raw)) return { ok: false, id: idForError, error: "malformed record" };
    const r = raw;

    // Повторная отправка того же id — уже приняли, не ошибка (см. п.13: повтор не создаёт дублей).
    if (existsByIdStmt.get(r.id)) return { ok: true, id: r.id, subjectKeyB64: r.subjectKeyB64 };

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
      const p = rawPresence as { chatPort?: unknown; callsign?: unknown; faction?: unknown; appVersion?: unknown; wireVersions?: unknown } | undefined;
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
      );
    },

    /** Устройство подтверждает применённые правки мастера — только после этого они перестают доставляться (повтор безопасен: правки идемпотентны). */
    acknowledge(subjectKey: string, ackIds: unknown[]) {
      for (const id of ackIds.slice(0, MAX_BATCH)) {
        if (typeof id === "string") markDeliveredStmt.run(id, subjectKey);
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
