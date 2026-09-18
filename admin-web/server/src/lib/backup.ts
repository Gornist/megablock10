import { mkdirSync, readdirSync, unlinkSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { join } from "node:path";
import type { Db } from "../db/index.js";

const FILE_PREFIX = "mb10-admin-";
const FILE_SUFFIX = ".sqlite";
const DEFAULT_RETENTION = 20;

/**
 * Резервная копия БД через встроенный VACUUM INTO — консистентный снимок "на
 * лету" без остановки сервера и без гонки с WAL, в отличие от простого
 * копирования живого файла. Раньше единственная копия состояния игры лежала
 * на ноутбуке, который можно было в крайнем случае унести домой целиком;
 * на выделенной машине это уже единственный экземпляр, так что бэкап
 * обязателен, а не опционален.
 *
 * Имя файла включает случайный суффикс, а не только время — на выделенной
 * машине бэкапы могут запуститься чаще, чем меняется секунда в
 * ISO-таймстампе, и без суффикса второй VACUUM INTO упал бы на "file exists".
 */
export function runBackup(db: Db, dir: string, retention = DEFAULT_RETENTION): string {
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const suffix = randomBytes(3).toString("hex");
  const path = join(dir, `${FILE_PREFIX}${stamp}-${suffix}${FILE_SUFFIX}`);
  db.prepare(`VACUUM INTO ?`).run(path);
  pruneOldBackups(dir, retention);
  return path;
}

/** Имена — ISO-таймстамп в префиксе, так что лексикографическая сортировка строк = хронологическая. */
function pruneOldBackups(dir: string, retention: number): void {
  const files = readdirSync(dir)
    .filter((f) => f.startsWith(FILE_PREFIX) && f.endsWith(FILE_SUFFIX))
    .sort()
    .reverse();
  for (const f of files.slice(retention)) {
    unlinkSync(join(dir, f));
  }
}

/**
 * Периодический бэкап фоном — вызывается только из index.ts (реального
 * процесса), не из buildApp()/тестов, чтобы не плодить файлы на диске при
 * каждом прогоне тестового набора. Делает один бэкап сразу при старте (не
 * ждать первого интервала на всю игру) и дальше по расписанию.
 */
export function scheduleBackups(db: Db, dir: string, intervalMs: number, retention = DEFAULT_RETENTION): () => void {
  const tryBackup = () => {
    try {
      runBackup(db, dir, retention);
    } catch (err) {
      console.error("backup failed:", err);
    }
  };

  tryBackup();
  const timer = setInterval(tryBackup, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
