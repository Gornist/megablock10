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
}

/** 32 случайных байта в hex — индивидуальный секрет каждого дисплея (одинаковый на всю партию не годится). */
export function newDisplaySecret(): string {
  return randomBytes(32).toString("hex");
}

export function secretKey(row: Pick<DisplayRow, "secret">): Buffer {
  return Buffer.from(row.secret, "hex");
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
        `INSERT INTO displays (id, name, ip, port, width, height, enabled, secret, created_at, updated_at)
         VALUES (@id, @name, @ip, @port, @width, @height, @enabled, @secret, @now, @now)`,
      )
      .run({ id, ...cfg, enabled: cfg.enabled ? 1 : 0, secret, now });
  }

  update(id: string, cfg: DisplayConfigInput): void {
    this.db
      .prepare(`UPDATE displays SET name = @name, ip = @ip, port = @port, width = @width, height = @height, enabled = @enabled, updated_at = @now WHERE id = @id`)
      .run({ id, ...cfg, enabled: cfg.enabled ? 1 : 0, now: Date.now() });
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

  /** TCP-соединение открылось (подпись ещё не проверена) — для «последнее соединение». */
  markConnected(id: string, at: number): void {
    this.db.prepare(`UPDATE displays SET last_connected_at = ? WHERE id = ?`).run(at, id);
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
