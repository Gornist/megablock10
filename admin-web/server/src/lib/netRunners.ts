import { createHash } from "node:crypto";
import type { Db } from "../db/index.js";
import { parseSafe } from "./json.js";

/**
 * Допуск нетраннера в «Сеть» (docs/netrun.md, «Решения владельца»): после флэтлайна игрок заблокирован, «пощадить» решает мастер
 * в коллекторе — он источник правды, Мост читает флаг (runner.blocked в Мосте — быстрая защита до ответа коллектора).
 * Программа персонажа не убивает: флаг и карточка «ФЛЭТЛАЙН» — только повод мастеру решить.
 */

export interface NetRunnerFlag {
  runnerKey: string;
  blocked: boolean;
  reason: string | null;
  callsign: string | null;
  session: string | null;
  node: string | null;
  terminal: string | null;
  /** Подробности флэтлайна из записи мира: cause, disconnect, left_in_node, alert. */
  detail: Record<string, unknown> | null;
  blockedAt: number | null;
  sparedAt: number | null;
  sparedBy: string | null;
  /** false — флаг ещё не записан в документ runner Моста (или Моста не было на связи) — догоняется при подключении. */
  bridgeSynced: boolean;
  updatedAt: number;
}

interface Row {
  runner_key: string;
  blocked: number;
  reason: string | null;
  callsign: string | null;
  session: string | null;
  node: string | null;
  terminal: string | null;
  detail: string | null;
  blocked_at: number | null;
  last_flatline_at: number | null;
  spared_at: number | null;
  spared_by: string | null;
  bridge_synced: number;
  updated_at: number;
}

const toFlag = (r: Row): NetRunnerFlag => ({
  runnerKey: r.runner_key,
  blocked: r.blocked === 1,
  reason: r.reason,
  callsign: r.callsign,
  session: r.session,
  node: r.node,
  terminal: r.terminal,
  detail: parseSafe<Record<string, unknown>>(r.detail),
  blockedAt: r.blocked_at,
  sparedAt: r.spared_at,
  sparedBy: r.spared_by,
  bridgeSynced: r.bridge_synced === 1,
  updatedAt: r.updated_at,
});

/**
 * Ключ игрока в коллекторе — обычный base64 с «=» (как subject_key в changes и как его пишут телефоны). Принимаем и base64url без «=»
 * (адрес в браузере, старые записи) и приводим к виду коллектора; пустое и мусор — null.
 */
export function normalizeRunnerKey(raw: string): string | null {
  if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(raw) || raw.length > 400) return null;
  const std = raw.replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "");
  return std + "=".repeat((4 - (std.length % 4)) % 4);
}

/**
 * Идентификатор документа `runner` в Мосте: `r_` + первые 32 hex SHA-256 строки ключа (так Мост хранит нетраннеров; сам ключ
 * лежит в `data.key`). Ключ — обычный base64, как у телефона.
 */
export function bridgeRunnerDocId(key: string): string {
  return `r_${createHash("sha256").update(key).digest("hex").slice(0, 32)}`;
}

export interface FlatlineInput {
  /** Значение `runner` из записи NET_FLATLINE (формат Моста). */
  runner: string;
  happenedAt: number;
  receivedAt: number;
  session: string | null;
  node: string | null;
  terminal: string | null;
  callsign: string | null;
  cause: string | null;
  disconnect: boolean;
  leftInNode: number | null;
  alert: string | null;
}

/** Допуск «может входить в Сеть» (белый список): решение мастера по игроку, независимо от блокировки после флэтлайна. */
export interface NetRunnerAccess {
  runnerKey: string;
  allowed: boolean;
  updatedBy: string | null;
  updatedAt: number;
}

export function createNetRunners(db: Db) {
  const accessGetStmt = db.prepare(`SELECT runner_key, allowed, updated_by, updated_at FROM net_runner_access WHERE runner_key = ?`);
  const accessListStmt = db.prepare(`SELECT runner_key, allowed, updated_by, updated_at FROM net_runner_access`);
  const accessSetStmt = db.prepare(`
    INSERT INTO net_runner_access (runner_key, allowed, updated_by, updated_at) VALUES (@key, @allowed, @by, @at)
    ON CONFLICT(runner_key) DO UPDATE SET allowed = @allowed, updated_by = @by, updated_at = @at
  `);
  type AccessRow = { runner_key: string; allowed: number; updated_by: string | null; updated_at: number };
  const toAccess = (r: AccessRow): NetRunnerAccess => ({ runnerKey: r.runner_key, allowed: r.allowed === 1, updatedBy: r.updated_by, updatedAt: r.updated_at });

  const getStmt = db.prepare(`SELECT * FROM net_runner_flags WHERE runner_key = ?`);
  const listStmt = db.prepare(`SELECT * FROM net_runner_flags ORDER BY blocked DESC, COALESCE(blocked_at, spared_at, 0) DESC`);
  const upsertBlockStmt = db.prepare(`
    INSERT INTO net_runner_flags (runner_key, blocked, reason, callsign, session, node, terminal, detail, blocked_at, last_flatline_at, spared_at, spared_by, bridge_synced, updated_at)
    VALUES (@key, 1, @reason, @callsign, @session, @node, @terminal, @detail, @at, @happenedAt, NULL, NULL, 0, @at)
    ON CONFLICT(runner_key) DO UPDATE SET
      blocked = 1, reason = @reason, callsign = COALESCE(@callsign, callsign), session = @session, node = @node, terminal = @terminal,
      detail = @detail, blocked_at = @at, last_flatline_at = @happenedAt, spared_at = NULL, spared_by = NULL, bridge_synced = 0, updated_at = @at
  `);
  const spareStmt = db.prepare(`UPDATE net_runner_flags SET blocked = 0, spared_at = @at, spared_by = @by, bridge_synced = 0, updated_at = @at WHERE runner_key = @key`);
  const markSyncedStmt = db.prepare(`UPDATE net_runner_flags SET bridge_synced = 1 WHERE runner_key = ? AND updated_at = ?`);
  const unsyncedStmt = db.prepare(`SELECT * FROM net_runner_flags WHERE bridge_synced = 0`);

  return {
    /** Допуск игрока; нет записи — мастер ещё не решал (в Мост «allowed» тогда не пишется, пока игрок не отмечен нетраннером). */
    access(key: string): NetRunnerAccess | null {
      const r = accessGetStmt.get(key) as AccessRow | undefined;
      return r ? toAccess(r) : null;
    },

    accessList(): NetRunnerAccess[] {
      return (accessListStmt.all() as AccessRow[]).map(toAccess);
    },

    setAllowed(key: string, allowed: boolean, by: string, now: number): void {
      accessSetStmt.run({ key, allowed: allowed ? 1 : 0, by, at: now });
    },

    get(key: string): NetRunnerFlag | null {
      const r = getStmt.get(key) as Row | undefined;
      return r ? toFlag(r) : null;
    },

    list(): NetRunnerFlag[] {
      return (listStmt.all() as Row[]).map(toFlag);
    },

    /**
     * Флэтлайн из записи мира (NET_FLATLINE): игрок заблокирован до решения мастера. Запись, которая случилась раньше «пощады»,
     * заново не блокирует (догнавший очередь Мост или восстановление из бэкапа не должны отменять решение мастера).
     * Возвращает true, если флаг поставлен.
     */
    onFlatline(f: FlatlineInput): boolean {
      const key = normalizeRunnerKey(f.runner);
      if (!key) return false;
      const existing = getStmt.get(key) as Row | undefined;
      if (existing?.spared_at != null && f.happenedAt <= existing.spared_at) return false;
      upsertBlockStmt.run({
        key,
        reason: f.disconnect ? "обрыв до флэтлайна" : (f.cause ?? "флэтлайн"),
        callsign: f.callsign,
        session: f.session,
        node: f.node,
        terminal: f.terminal,
        detail: JSON.stringify({ cause: f.cause, disconnect: f.disconnect, left_in_node: f.leftInNode, alert: f.alert }),
        at: f.receivedAt,
        happenedAt: f.happenedAt,
      });
      return true;
    },

    /** «Пощадить»: снять блокировку. false — флага нет (нечего щадить). Повтор безопасен. */
    spare(key: string, by: string, now: number): boolean {
      const existing = getStmt.get(key) as Row | undefined;
      if (!existing) return false;
      if (existing.blocked === 1) spareStmt.run({ key, by, at: now });
      return true;
    },

    /** Закрыть допуск вручную — без флэтлайна (мастер решил сам). */
    block(key: string, reason: string, now: number): void {
      const existing = getStmt.get(key) as Row | undefined;
      upsertBlockStmt.run({
        key,
        reason: reason || "закрыто мастером",
        callsign: existing?.callsign ?? null,
        session: null,
        node: null,
        terminal: null,
        detail: JSON.stringify({ manual: true }),
        at: now,
        happenedAt: now,
      });
    },

    /** Флаги, ещё не записанные в Мост (Ф7): и снятые, и поставленные — Мост должен узнать об обоих. */
    unsynced(): NetRunnerFlag[] {
      return (unsyncedStmt.all() as Row[]).map(toFlag);
    },

    /** Помечает записанным, только если флаг с тех пор не менялся (мастер мог нажать ещё раз, пока шла запись). */
    markSynced(key: string, updatedAt: number): void {
      markSyncedStmt.run(key, updatedAt);
    },
  };
}

export type NetRunners = ReturnType<typeof createNetRunners>;
