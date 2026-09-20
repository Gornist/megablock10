/** Тир узла/шарда словами — так же, как в приложении (База / Сложно / Кошмар); принимает и имя тира, и уровень. */
export function tierLabel(tier: string | number): string {
  const map: Record<string, string> = { BASE: "База", HARD: "Сложно", NIGHTMARE: "Кошмар", "1": "База", "2": "Сложно", "3": "Кошмар" };
  return map[String(tier)] ?? String(tier);
}

export function shortKey(keyB64: string, len = 10): string {
  return keyB64.length <= len * 2 ? keyB64 : `${keyB64.slice(0, len)}…${keyB64.slice(-4)}`;
}

export function formatTime(ms: number | null): string {
  if (!ms) return "—";
  const d = new Date(ms);
  return d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function formatAgo(ms: number | null): string {
  if (!ms) return "—";
  const diff = Date.now() - ms;
  if (diff < 0) return "сейчас";
  const s = Math.floor(diff / 1000);
  if (s < 60) return `${s}с назад`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}м назад`;
  const h = Math.floor(m / 60);
  return `${h}ч назад`;
}

export function formatDateTime(ms: number | null): string {
  if (!ms) return "—";
  return new Date(ms).toLocaleString("ru-RU", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

/** Значение для <input type="datetime-local"> в локальном времени браузера. */
export function toDatetimeLocal(ms: number): string {
  const d = new Date(ms - new Date(ms).getTimezoneOffset() * 60_000);
  return d.toISOString().slice(0, 16);
}

export function fromDatetimeLocal(value: string): number | null {
  const ms = new Date(value).getTime();
  return Number.isFinite(ms) ? ms : null;
}

/** Целое с разделителем тысяч: 12 500 */
export function formatNumber(n: number): string {
  return n.toLocaleString("ru-RU");
}
