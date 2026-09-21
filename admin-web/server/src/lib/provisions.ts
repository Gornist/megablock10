import { randomUUID } from "node:crypto";
import type { FastifyRequest } from "fastify";
import type { ProvisionItem } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { encodeProvisionQr } from "./mb10QrCodec.js";

/**
 * QR персонажа (docs/provisioning-qr.md, docs/character-reissue.md): мастер выдаёт код, телефон при первом запуске применяет его
 * и присылает CHARACTER_CREATED с source_ref = id выдачи. Сервер привязывает id к ключу первого телефона — код одноразовый;
 * повторная выдача создаёт новый код, помнит прежний ключ и после привязки помечает его «заменён» (см. replaced_keys).
 */

const PROVISION_MAX_TEXT = 40;
export const PROVISION_MAX_BALANCE = 1_000_000;

export interface ProvisionParams {
  callsign: string;
  faction: string;
  balance: number;
  ram: number;
}

/** Те же границы, что у ProvisionRules на телефоне: напечатать можно и ошибку, а на первом запуске исправить уже нечем. */
export function validateProvisionParams(p: { callsign: unknown; faction: unknown; balance: unknown; ram: unknown }): { ok: true; value: ProvisionParams } | { ok: false; error: string } {
  if (typeof p.callsign !== "string" || p.callsign.trim() === "") return { ok: false, error: "callsign is required" };
  if (p.callsign.length > PROVISION_MAX_TEXT) return { ok: false, error: `callsign is too long, max ${PROVISION_MAX_TEXT}` };
  if (typeof p.faction !== "string") return { ok: false, error: "faction must be a string" };
  if (p.faction.length > PROVISION_MAX_TEXT) return { ok: false, error: `faction is too long, max ${PROVISION_MAX_TEXT}` };
  if (!Number.isInteger(p.balance) || (p.balance as number) < 0 || (p.balance as number) > PROVISION_MAX_BALANCE) {
    return { ok: false, error: `balance must be an integer from 0 to ${PROVISION_MAX_BALANCE}` };
  }
  if (!Number.isInteger(p.ram) || ((p.ram as number) !== 0 && ((p.ram as number) < 6 || (p.ram as number) > 13))) {
    return { ok: false, error: "ram must be 0 (default) or an integer from 6 to 13" };
  }
  return { ok: true, value: { callsign: p.callsign.trim(), faction: p.faction.trim(), balance: p.balance as number, ram: p.ram as number } };
}

interface ProvisionRow {
  id: string;
  callsign: string;
  faction: string;
  balance: number;
  ram: number;
  created_by: string;
  created_at: number;
  replaces_key: string | null;
  bound_key: string | null;
  bound_at: number | null;
  void: number;
}

export function createProvision(db: Db, masterName: string, params: ProvisionParams, replacesKey: string | null = null, now = Date.now()): string {
  const id = randomUUID();
  db.transaction(() => {
    if (replacesKey) {
      // Действителен один код на прежний ключ: неиспользованные прошлые перевыдачи и код, которым играл прежний телефон, гасим.
      db.prepare(`UPDATE provisions SET void = 1 WHERE replaces_key = ? AND bound_key IS NULL`).run(replacesKey);
      db.prepare(`UPDATE provisions SET void = 1 WHERE bound_key = ?`).run(replacesKey);
    }
    db.prepare(
      `INSERT INTO provisions (id, callsign, faction, balance, ram, created_by, created_at, replaces_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(id, params.callsign, params.faction, params.balance, params.ram, masterName, now, replacesKey);
  })();
  return id;
}

export type BindResult = { ok: true } | { ok: false; error: string };

/**
 * Проверка при приёме CHARACTER_CREATED с source_ref: привязывает выданный код к ключу или отказывает. Неизвестный код (не выдан этим
 * коллектором — например, старый стенд или другой мастер) не блокируем: раньше такие записи принимались, и ломать это незачем.
 * Вызывать внутри транзакции приёма батча.
 */
export function bindProvision(db: Db, id: string, key: string, now = Date.now()): BindResult {
  const row = db.prepare(`SELECT * FROM provisions WHERE id = ?`).get(id) as ProvisionRow | undefined;
  if (!row || row.bound_key === key) return { ok: true };

  if (row.bound_key !== null) {
    db.prepare(`INSERT OR IGNORE INTO provision_conflicts (provision_id, key, at) VALUES (?, ?, ?)`).run(id, key, now);
    return { ok: false, error: "provision code already applied on another device" };
  }
  if (row.void) return { ok: false, error: "provision code is no longer valid (issued again)" };

  db.prepare(`UPDATE provisions SET bound_key = ?, bound_at = ? WHERE id = ?`).run(key, now, id);
  if (row.replaces_key && row.replaces_key !== key) {
    db.prepare(`INSERT OR REPLACE INTO replaced_keys (old_key, new_key, at) VALUES (?, ?, ?)`).run(row.replaces_key, key, now);
  }
  return { ok: true };
}

/** Адрес сервера для QR: PUBLIC_URL, иначе тот, по которому мастер открыл дашборд (если это не localhost — с телефона он бесполезен). */
export function provisionConfig(request: FastifyRequest): { url: string; urlSource: "env" | "request" | "none"; secret: string } {
  const secret = process.env.GAME_SECRET ?? "";
  const env = (process.env.PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
  if (env) return { url: env, urlSource: "env", secret };
  const host = request.headers.host ?? "";
  const hostname = host.replace(/:\d+$/, "").replace(/^\[|\]$/g, "");
  if (host && !["localhost", "127.0.0.1", "::1", ""].includes(hostname)) return { url: `${request.protocol}://${host}`, urlSource: "request", secret };
  return { url: "", urlSource: "none", secret };
}

export function provisionQrString(p: Pick<ProvisionRow, "id" | "callsign" | "faction" | "balance" | "ram">, cfg: { url: string; secret: string }): string {
  return encodeProvisionQr({ id: p.id, url: cfg.url, secret: cfg.secret, callsign: p.callsign, faction: p.faction, balance: p.balance, ram: p.ram });
}

/** Ключи, которые не считаются игроками в сводках: заменённые на другой телефон и со сброшенной сессией (устройство свободно). */
export function replacedMap(db: Db): Map<string, string> {
  return new Map((db.prepare(`SELECT old_key, new_key FROM replaced_keys`).all() as { old_key: string; new_key: string }[]).map((r) => [r.old_key, r.new_key]));
}

export function replacesMap(db: Db): Map<string, string> {
  return new Map((db.prepare(`SELECT old_key, new_key FROM replaced_keys`).all() as { old_key: string; new_key: string }[]).map((r) => [r.new_key, r.old_key]));
}

export function listProvisions(db: Db, playerName: (key: string) => string): ProvisionItem[] {
  const conflicts = new Map(
    (db.prepare(`SELECT provision_id, COUNT(*) AS n FROM provision_conflicts GROUP BY provision_id`).all() as { provision_id: string; n: number }[]).map((r) => [r.provision_id, r.n]),
  );
  const rows = db.prepare(`SELECT * FROM provisions ORDER BY created_at DESC LIMIT 300`).all() as ProvisionRow[];
  return rows.map((r) => provisionItem(r, conflicts.get(r.id) ?? 0, playerName));
}

export function getProvision(db: Db, id: string, playerName: (key: string) => string): ProvisionItem | null {
  const row = db.prepare(`SELECT * FROM provisions WHERE id = ?`).get(id) as ProvisionRow | undefined;
  if (!row) return null;
  const n = (db.prepare(`SELECT COUNT(*) AS n FROM provision_conflicts WHERE provision_id = ?`).get(id) as { n: number }).n;
  return provisionItem(row, n, playerName);
}

function provisionItem(r: ProvisionRow, conflicts: number, playerName: (key: string) => string): ProvisionItem {
  return {
    id: r.id,
    callsign: r.callsign,
    faction: r.faction,
    balance: r.balance,
    ram: r.ram,
    createdAt: r.created_at,
    createdBy: r.created_by,
    replacesKey: r.replaces_key,
    replacesName: r.replaces_key ? playerName(r.replaces_key) : null,
    boundKey: r.bound_key,
    boundName: r.bound_key ? playerName(r.bound_key) : null,
    boundAt: r.bound_at,
    void: r.void === 1,
    conflicts,
  };
}

export function rawProvision(db: Db, id: string): ProvisionRow | undefined {
  return db.prepare(`SELECT * FROM provisions WHERE id = ?`).get(id) as ProvisionRow | undefined;
}

export function provisionConflicts(db: Db): { provisionId: string; key: string; at: number; callsign: string; boundKey: string | null }[] {
  return (
    db
      .prepare(
        `SELECT c.provision_id AS provisionId, c.key, c.at, p.callsign, p.bound_key AS boundKey
         FROM provision_conflicts c JOIN provisions p ON p.id = c.provision_id`,
      )
      .all() as { provisionId: string; key: string; at: number; callsign: string; boundKey: string | null }[]
  );
}
