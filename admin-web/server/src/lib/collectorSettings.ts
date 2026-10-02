import type { Db } from "../db/index.js";

/** Настройки самого коллектора, которые мастер правит из дашборда (таблица collector_settings): ключ → строка. */
export function getSetting(db: Db, key: string): string | null {
  return (db.prepare(`SELECT value FROM collector_settings WHERE key = ?`).get(key) as { value: string } | undefined)?.value ?? null;
}

/** null — убрать настройку. */
export function setSetting(db: Db, key: string, value: string | null): void {
  if (value === null) db.prepare(`DELETE FROM collector_settings WHERE key = ?`).run(key);
  else db.prepare(`INSERT INTO collector_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`).run(key, value);
}
