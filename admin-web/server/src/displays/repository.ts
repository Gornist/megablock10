import { randomBytes } from "node:crypto";
import type { Db } from "../db/index.js";

/** Строка таблицы displays (db/index.ts) — только здесь в snake_case; наружу уходит DisplayItem (manager.ts), без секрета. */
export interface DisplayRow {
  id: string;
  name: string;
  ip: string;
  port: number;
  width: number;
  height: number;
  enabled: number;
  secret: string;
  hardware_id: string | null;
  fw_version: string | null;
  battery_mv: number | null;
  /** От топливомера; null — нет его (процент — по напряжению). */
  battery_pct: number | null;
  battery_rate: number | null;
  /** display_groups.id; null — без группы. */
  group_id: string | null;
  /** Узел (containers.id), которым точка стоит в мире; NULL — без узла. */
  node_id: string | null;
  // ── Звук (audio/, миграция 6) ──
  /** Роли из HELLO, JSON-массив; null — ещё не было HELLO (или старая прошивка дисплея). */
  roles: string | null;
  /** Канал-исключение: null — как у группы, "" — тишина. */
  audio_channel_id: string | null;
  /** Громкость-исключение 0…100; null — как у группы/канала. */
  audio_volume: number | null;
  /** Версия желаемого звукового состояния (seq AUDIO_STATE) и само состояние (JSON AudioStatePayload). */
  audio_version: number;
  audio_state: string | null;
  /** Что точка доложила в последнем HELLO (JSON AudioHelloStatus) и каталог карты (JSON string[] из LIST). */
  audio_reported: string | null;
  audio_catalog: string | null;
  rssi: number | null;
  last_seen_at: number | null;
  last_connected_at: number | null;
  last_error: string | null;
  last_error_at: number | null;
  desired_version: number;
  desired_qr: string | null;
  desired_label: string | null;
  displayed_version: number | null;
  displayed_at: number | null;
  created_at: number;
  updated_at: number;
}

export interface DisplayConfigInput {
  name: string;
  ip: string;
  port: number;
  width: number;
  height: number;
  enabled: boolean;
  /** Группа (display_groups.id); null или не задано — без группы. */
  groupId?: string | null;
  /** Узел (containers.id); null или не задано — без узла. Одна точка — один узел (проверяет маршрут). */
  nodeId?: string | null;
}

export interface DisplayGroupRow {
  id: string;
  name: string;
  created_at: number;
  /** Фон группы: канал (null — тишина) и громкость (null — как у канала). */
  audio_channel_id: string | null;
  audio_volume: number | null;
}

/** 32 случайных байта в hex — индивидуальный секрет каждого дисплея (одинаковый на всю партию не годится). */
export function newDisplaySecret(): string {
  return randomBytes(32).toString("hex");
}

export function secretKey(row: Pick<DisplayRow, "secret">): Buffer {
  return Buffer.from(row.secret, "hex");
}

/** Роли точки из HELLO (displays.roles, JSON); нет — старая прошивка дисплея. */
export function parseRoles(raw: string | null): string[] {
  if (!raw) return ["display"];
  try {
    const v = JSON.parse(raw) as unknown;
    return Array.isArray(v) && v.every((x) => typeof x === "string") ? v : ["display"];
  } catch {
    return ["display"];
  }
}

/** Есть ли у точки роль (displays.roles): «audio» — звуковая точка. */
export function hasRole(row: Pick<DisplayRow, "roles">, role: string): boolean {
  return parseRoles(row.roles).includes(role);
}

export class DisplayRepository {
  constructor(private readonly db: Db) {}

  list(): DisplayRow[] {
    return this.db.prepare(`SELECT * FROM displays ORDER BY id`).all() as DisplayRow[];
  }

  get(id: string): DisplayRow | undefined {
    return this.db.prepare(`SELECT * FROM displays WHERE id = ?`).get(id) as DisplayRow | undefined;
  }

  create(id: string, cfg: DisplayConfigInput, secret: string): void {
    const now = Date.now();
    this.db
      .prepare(
        `INSERT INTO displays (id, name, ip, port, width, height, enabled, group_id, node_id, secret, created_at, updated_at)
         VALUES (@id, @name, @ip, @port, @width, @height, @enabled, @groupId, @nodeId, @secret, @now, @now)`,
      )
      .run({ id, ...cfg, enabled: cfg.enabled ? 1 : 0, groupId: cfg.groupId ?? null, nodeId: cfg.nodeId ?? null, secret, now });
  }

  update(id: string, cfg: DisplayConfigInput): void {
    this.db
      .prepare(
        `UPDATE displays SET name = @name, ip = @ip, port = @port, width = @width, height = @height, enabled = @enabled, group_id = @groupId,
           node_id = @nodeId, updated_at = @now WHERE id = @id`,
      )
      .run({ id, ...cfg, enabled: cfg.enabled ? 1 : 0, groupId: cfg.groupId ?? null, nodeId: cfg.nodeId ?? null, now: Date.now() });
  }

  // ── Узлы ──

  setNode(id: string, nodeId: string | null): void {
    this.db.prepare(`UPDATE displays SET node_id = ?, updated_at = ? WHERE id = ?`).run(nodeId, Date.now(), id);
  }

  /** Точка, уже привязанная к узлу (кроме exceptId), — одна точка на узел. */
  displayOfNode(nodeId: string, exceptId?: string): DisplayRow | undefined {
    return this.db.prepare(`SELECT * FROM displays WHERE node_id = ? AND id != ?`).get(nodeId, exceptId ?? "") as DisplayRow | undefined;
  }

  nodeExists(nodeId: string): boolean {
    return this.db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get(nodeId) !== undefined;
  }

  // ── Группы ──

  listGroups(): DisplayGroupRow[] {
    const rows = this.db.prepare(`SELECT * FROM display_groups`).all() as DisplayGroupRow[];
    // По алфавиту с кириллицей (COLLATE NOCASE в SQLite тоже знает только латиницу).
    return rows.sort((a, b) => a.name.localeCompare(b.name, "ru", { sensitivity: "base" }) || a.id.localeCompare(b.id));
  }

  getGroup(id: string): DisplayGroupRow | undefined {
    return this.db.prepare(`SELECT * FROM display_groups WHERE id = ?`).get(id) as DisplayGroupRow | undefined;
  }

  /** Без учёта регистра — в JS: lower() в SQLite понижает только латиницу, «Бар» и «бар» для него разные. */
  groupByName(name: string): DisplayGroupRow | undefined {
    const key = name.trim().toLocaleLowerCase("ru");
    return this.listGroups().find((g) => g.name.toLocaleLowerCase("ru") === key);
  }

  createGroup(name: string): DisplayGroupRow {
    const row: DisplayGroupRow = { id: `g-${randomBytes(4).toString("hex")}`, name, created_at: Date.now(), audio_channel_id: null, audio_volume: null };
    this.db.prepare(`INSERT INTO display_groups (id, name, created_at) VALUES (@id, @name, @created_at)`).run(row);
    return row;
  }

  renameGroup(id: string, name: string): void {
    this.db.prepare(`UPDATE display_groups SET name = ? WHERE id = ?`).run(name, id);
  }

  /** Точки группы остаются — без группы. */
  deleteGroup(id: string): boolean {
    this.db.prepare(`UPDATE displays SET group_id = NULL WHERE group_id = ?`).run(id);
    return this.db.prepare(`DELETE FROM display_groups WHERE id = ?`).run(id).changes > 0;
  }

  setGroup(id: string, groupId: string | null): void {
    this.db.prepare(`UPDATE displays SET group_id = ?, updated_at = ? WHERE id = ?`).run(groupId, Date.now(), id);
  }

  /** Роли и звук из HELLO — сохраняются, только если точка их прислала (старая прошивка дисплея — не трогаем). */
  setRoles(id: string, roles: unknown, audio: unknown): void {
    if (Array.isArray(roles) && roles.every((r) => typeof r === "string")) {
      this.db.prepare(`UPDATE displays SET roles = ? WHERE id = ?`).run(JSON.stringify(roles.slice(0, 8)), id);
    }
    if (audio && typeof audio === "object") this.db.prepare(`UPDATE displays SET audio_reported = ? WHERE id = ?`).run(JSON.stringify(audio).slice(0, 8192), id);
  }

  setSecret(id: string, secret: string): void {
    this.db.prepare(`UPDATE displays SET secret = ?, updated_at = ? WHERE id = ?`).run(secret, Date.now(), id);
  }

  delete(id: string): boolean {
    this.db.prepare(`DELETE FROM display_battery_samples WHERE display_id = ?`).run(id);
    return this.db.prepare(`DELETE FROM displays WHERE id = ?`).run(id).changes > 0;
  }

  /** Новая картинка: версия строго больше всего, что сервер отправлял и что дисплей показывал (правило «старое не принимать»). */
  assignDesired(id: string, qr: string, label: string): number {
    return this.db.transaction(() => {
      const row = this.get(id);
      if (!row) throw new Error(`unknown display ${id}`);
      const version = Math.max(row.desired_version, row.displayed_version ?? 0) + 1;
      this.db.prepare(`UPDATE displays SET desired_version = ?, desired_qr = ?, desired_label = ? WHERE id = ?`).run(version, qr, label, id);
      return version;
    })();
  }

  /** Дисплей показывает версию новее отправляемой (восстановили БД из копии) — отправляемая перенумеровывается выше. */
  bumpDesiredVersion(id: string, version: number): void {
    this.db.prepare(`UPDATE displays SET desired_version = MAX(desired_version, ?) WHERE id = ?`).run(version, id);
  }

  /** Связь есть и подпись HELLO сошлась. */
  markSeen(
    id: string,
    at: number,
    info: { hardwareId?: string; fw?: string; batteryMv?: number; batteryPct?: number; batteryRate?: number; rssi?: number; displayedVersion: number },
  ): void {
    this.db
      .prepare(
        `UPDATE displays SET last_seen_at = @at, last_connected_at = @at,
           hardware_id = COALESCE(@hw, hardware_id), fw_version = COALESCE(@fw, fw_version),
           battery_mv = COALESCE(@battery, battery_mv), battery_pct = @pct, battery_rate = @rate, rssi = COALESCE(@rssi, rssi),
           displayed_version = @displayed
         WHERE id = @id`,
      )
      .run({
        id,
        at,
        hw: typeof info.hardwareId === "string" ? info.hardwareId.slice(0, 64) : null,
        fw: typeof info.fw === "string" ? info.fw.slice(0, 32) : null,
        battery: Number.isInteger(info.batteryMv) ? info.batteryMv : null,
        // Процент и скорость — не COALESCE: вынули топливомер — точка перестаёт их слать, старые не должны висеть вечно.
        pct: Number.isInteger(info.batteryPct) && info.batteryPct! >= 0 && info.batteryPct! <= 100 ? info.batteryPct : null,
        rate: typeof info.batteryRate === "number" && Number.isFinite(info.batteryRate) ? info.batteryRate : null,
        rssi: Number.isInteger(info.rssi) ? info.rssi : null,
        displayed: info.displayedVersion,
      });
  }

  /** Точка истории заряда — не чаще раза в minIntervalMs; заодно чистит старше keepMs. */
  recordBattery(id: string, at: number, mv: number | null, pct: number | null, minIntervalMs: number, keepMs: number): void {
    if (mv === null && pct === null) return;
    const last = this.db.prepare(`SELECT MAX(at) AS at FROM display_battery_samples WHERE display_id = ?`).get(id) as { at: number | null };
    if (last.at !== null && at - last.at < minIntervalMs) return;
    this.db.prepare(`INSERT OR REPLACE INTO display_battery_samples (display_id, at, mv, pct) VALUES (?, ?, ?, ?)`).run(id, at, mv, pct);
    this.db.prepare(`DELETE FROM display_battery_samples WHERE display_id = ? AND at < ?`).run(id, at - keepMs);
  }

  batterySamples(id: string, since: number): { at: number; mv: number | null; pct: number | null }[] {
    return this.db.prepare(`SELECT at, mv, pct FROM display_battery_samples WHERE display_id = ? AND at >= ? ORDER BY at`).all(id, since) as {
      at: number;
      mv: number | null;
      pct: number | null;
    }[];
  }

  markDisplayed(id: string, version: number, at: number): void {
    this.db
      .prepare(`UPDATE displays SET displayed_version = MAX(COALESCE(displayed_version, 0), ?), displayed_at = ?, last_seen_at = ?, last_error = NULL, last_error_at = NULL WHERE id = ?`)
      .run(version, at, at, id);
  }

  setError(id: string, error: string, at: number): void {
    this.db.prepare(`UPDATE displays SET last_error = ?, last_error_at = ? WHERE id = ?`).run(error.slice(0, 500), at, id);
  }

  clearError(id: string): void {
    this.db.prepare(`UPDATE displays SET last_error = NULL, last_error_at = NULL WHERE id = ?`).run(id);
  }
}
