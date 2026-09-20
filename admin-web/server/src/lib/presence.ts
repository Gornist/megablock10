/**
 * Присутствие игроков по heartbeat: телефон раз в ~30 с шлёт POST /api/changes даже пустым батчем (чтобы получить правки мастера).
 * Раньше «на связи» считалось только по последним ЗАПИСЯМ изменений, и игрок, который просто ходит по площадке, выглядел офлайн.
 * Хранится в памяти: после рестарта сервера первый же heartbeat (≤30 с) восстанавливает картину, писать это в БД незачем.
 */
const seen = new Map<string, number>();

/**
 * Где искать телефон в сети: адрес, с которого пришёл heartbeat (его видит сам сервер — заявленному телефоном адресу верить нельзя),
 * и порт чат-сервера приложения, который телефон сообщает сам. Нужно для запасного обнаружения пиров, когда mDNS/NSD капризничает
 * (docs/network-spec.md, §7): в ответе на heartbeat сервер отдаёт остальных недавно видимых игроков.
 */
export interface PresenceDetails {
  host: string;
  port: number;
  callsign: string;
  faction: string;
}
const details = new Map<string, PresenceDetails>();

export function touchPresence(subjectKeyB64: string, at: number = Date.now(), info?: PresenceDetails) {
  if (!subjectKeyB64) return;
  seen.set(subjectKeyB64, at);
  if (info) details.set(subjectKeyB64, info);
}

/** IPv4-адрес из request.ip (Node отдаёт «::ffff:192.0.2.20» для v4 через dual-stack сокет); всё остальное — null. */
export function ipv4Of(ip: string | undefined): string | null {
  const plain = (ip ?? "").replace(/^::ffff:/i, "");
  return /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.test(plain) && plain.split(".").every((n) => Number(n) <= 255) ? plain : null;
}

/** Другие игроки, замеченные после [since] (мс), с известным адресом и портом. */
export function peersSince(since: number, exceptKey: string): Array<PresenceDetails & { pubKeyB64: string }> {
  const out: Array<PresenceDetails & { pubKeyB64: string }> = [];
  for (const [key, at] of seen) {
    const d = details.get(key);
    if (key !== exceptKey && at > since && d) out.push({ pubKeyB64: key, ...d });
  }
  return out;
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
  details.clear();
}
