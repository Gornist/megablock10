import { randomBytes, randomUUID } from "node:crypto";
import type { FastifyReply, FastifyRequest } from "fastify";
import type { Db } from "../db/index.js";
import { hashToken } from "./crypto.js";

const SESSION_TTL_MS = 24 * 60 * 60 * 1000; // сутки, см. §9 ТЗ

export interface Master {
  id: string;
  name: string;
}

/** Схема auth-таблиц — отдельно от основной schema.ts, потому что появилась позже (Ф8 плана двигаем раньше, чтобы закрыть §9 целиком сразу). */
export function ensureAuthSchema(db: Db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS masters (
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL UNIQUE,
      token_hash  TEXT NOT NULL,
      created_at  INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token       TEXT PRIMARY KEY,
      master_id   TEXT NOT NULL,
      created_at  INTEGER NOT NULL,
      expires_at  INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS audit_master (
      id         TEXT PRIMARY KEY,
      master_id  TEXT NOT NULL,
      action     TEXT NOT NULL,
      detail     TEXT,
      at         INTEGER NOT NULL
    );
  `);
}

export function createMaster(db: Db, name: string): string {
  const token = randomBytes(24).toString("base64url");
  db.prepare(`INSERT INTO masters (id, name, token_hash, created_at) VALUES (?, ?, ?, ?)`).run(
    randomUUID(),
    name,
    hashToken(token),
    Date.now(),
  );
  return token;
}

export function login(db: Db, name: string, token: string): { sessionToken: string; master: Master; expiresAt: number } | null {
  const row = db.prepare(`SELECT id, name, token_hash FROM masters WHERE name = ?`).get(name) as
    | { id: string; name: string; token_hash: string }
    | undefined;
  if (!row || row.token_hash !== hashToken(token)) return null;

  const sessionToken = randomBytes(32).toString("base64url");
  const now = Date.now();
  const expiresAt = now + SESSION_TTL_MS;
  db.prepare(`INSERT INTO sessions (token, master_id, created_at, expires_at) VALUES (?, ?, ?, ?)`).run(
    sessionToken,
    row.id,
    now,
    expiresAt,
  );
  return { sessionToken, master: { id: row.id, name: row.name }, expiresAt };
}

/** Возвращает мастера по сессионному токену из заголовка Authorization: Bearer <token>, либо null. Не сама шлёт ответ — решение, что делать с отказом, за вызывающим роутом. */
export function authenticate(db: Db, request: FastifyRequest): Master | null {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length);
  const row = db.prepare(`SELECT master_id, expires_at FROM sessions WHERE token = ?`).get(token) as
    | { master_id: string; expires_at: number }
    | undefined;
  if (!row || row.expires_at < Date.now()) return null;
  const master = db.prepare(`SELECT id, name FROM masters WHERE id = ?`).get(row.master_id) as Master | undefined;
  return master ?? null;
}

/** Хелпер для защищённых роутов: отдаёт 401 и возвращает null, если токена нет/протух. */
export function requireMaster(db: Db, request: FastifyRequest, reply: FastifyReply): Master | null {
  const master = authenticate(db, request);
  if (!master) {
    reply.code(401).send({ error: "master token required" });
    return null;
  }
  return master;
}

export function logMasterAction(db: Db, masterId: string, action: string, detail: unknown) {
  db.prepare(`INSERT INTO audit_master (id, master_id, action, detail, at) VALUES (?, ?, ?, ?, ?)`).run(
    randomUUID(),
    masterId,
    action,
    detail === undefined ? null : JSON.stringify(detail),
    Date.now(),
  );
}
