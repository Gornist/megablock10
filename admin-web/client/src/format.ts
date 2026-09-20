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
