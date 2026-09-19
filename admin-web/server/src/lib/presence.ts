/**
 * Присутствие игроков по heartbeat: телефон раз в ~30 с шлёт POST /api/changes даже пустым батчем (чтобы получить правки мастера).
 * Раньше «на связи» считалось только по последним ЗАПИСЯМ изменений, и игрок, который просто ходит по площадке, выглядел офлайн.
 * Хранится в памяти: после рестарта сервера первый же heartbeat (≤30 с) восстанавливает картину, писать это в БД незачем.
 */
const seen = new Map<string, number>();

export function touchPresence(subjectKeyB64: string, at: number = Date.now()) {
  if (subjectKeyB64) seen.set(subjectKeyB64, at);
}

export function lastPresence(subjectKeyB64: string): number {
  return seen.get(subjectKeyB64) ?? 0;
}

/** Ключи, замеченные heartbeat-ом после [since] (мс). */
export function presentSince(since: number): string[] {
  const out: string[] = [];
  for (const [key, at] of seen) if (at > since) out.push(key);
  return out;
}

export function resetPresence() {
  seen.clear();
}
