import type { Db } from "../db/index.js";

/**
 * Кэш дорогих агрегатов (listPlayerSummaries/listNodeSummaries/
 * listSlotRegistry — каждый пересчитывает историю с нуля), инвалидируемый
 * НЕ по времени, а по факту записи в БД. Обычный TTL-кэш здесь сломал бы
 * то самое "мастер поправил — игрок/дашборд увидели сразу" (§6.3, §6.5
 * ТЗ): между правкой и истечением TTL дашборд показывал бы старое значение,
 * а не то, что мастер только что применил, — на живой игре это выглядело
 * бы как "я же исправил, почему опять не так".
 *
 * total_changes() — встроенный счётчик SQLite: число строк, изменённых
 * этим соединением с момента открытия. Растёт при КАЖДОЙ вставке/апдейте
 * (новый ChangeRecord с устройства, override, claim/revoke) — сравнение с
 * ним даёт точную инвалидацию без необходимости дёргать cache.invalidate()
 * из каждого write-пути руками и без риска забыть это сделать в новом.
 * Смысл кэша — не "отдавать чуть устаревшее", а "не пересчитывать заново,
 * когда между двумя опросами (несколько открытых вкладок дашборда, каждая
 * поллит раз в 8с) буквально ничего не изменилось".
 */
export function cachedByDbVersion<T>(db: Db, compute: () => T): () => T {
  const totalChangesStmt = db.prepare("SELECT total_changes() AS n");
  let cached: { value: T; version: number } | null = null;

  return () => {
    const version = (totalChangesStmt.get() as { n: number }).n;
    if (cached && cached.version === version) return cached.value;
    const value = compute();
    cached = { value, version };
    return value;
  };
}
