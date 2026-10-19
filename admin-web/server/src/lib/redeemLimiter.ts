/**
 * Защита ввода короткого кода персонажа от подбора (POST /api/provisions/redeem, без мастера: телефон ещё ничего не знает).
 * Считаются только НЕВЕРНЫЕ попытки: 5 подряд с одного IP — пауза 5 минут; плюс общий потолок неверных в час на весь сервер
 * (по умолчанию 100) — тогда 429 всем и тревога мастеру. Пока лимит сработал, код вообще не проверяется — ответ не подсказывает,
 * верный он или нет. Верный код сбрасывает счётчик своего IP. Состояние в памяти: коллектор однопроцессный, после рестарта
 * счётчики начинаются заново (стоимость подбора это не меняет: 31^6 вариантов, ≤100 попыток в час).
 */
export const REDEEM_IP_FAILS = 5;
export const REDEEM_IP_PAUSE_MS = 5 * 60_000;
export const REDEEM_GLOBAL_WINDOW_MS = 60 * 60_000;

export type RedeemGate = { ok: true } | { ok: false; retryAfterSec: number; scope: "ip" | "global" };

export interface RedeemLimiter {
  /** Можно ли вообще проверять код от этого IP сейчас. */
  check(ip: string, now?: number): RedeemGate;
  fail(ip: string, now?: number): void;
  success(ip: string): void;
  /** Когда общий потолок срабатывал последний раз (мс) — для тревоги мастеру; null — не срабатывал или давно. */
  globalBlockedAt(now?: number): number | null;
  /** Только для тестов: забыть всё состояние (общий экземпляр живёт, пока жив процесс). */
  reset(): void;
}

export function createRedeemLimiter(globalPerHour = Number(process.env.REDEEM_GLOBAL_PER_HOUR ?? 100)): RedeemLimiter {
  const perIp = new Map<string, { fails: number; blockedUntil: number }>();
  let failTimes: number[] = [];
  let lastGlobalBlock: number | null = null;

  const prune = (now: number) => {
    failTimes = failTimes.filter((t) => now - t < REDEEM_GLOBAL_WINDOW_MS);
    if (perIp.size > 1000) for (const [ip, s] of perIp) if (s.blockedUntil <= now && s.fails === 0) perIp.delete(ip);
  };

  return {
    check(ip, now = Date.now()) {
      prune(now);
      if (globalPerHour > 0 && failTimes.length >= globalPerHour) {
        lastGlobalBlock = now;
        return { ok: false, scope: "global", retryAfterSec: Math.max(1, Math.ceil((failTimes[0] + REDEEM_GLOBAL_WINDOW_MS - now) / 1000)) };
      }
      const s = perIp.get(ip);
      if (s && s.blockedUntil > now) return { ok: false, scope: "ip", retryAfterSec: Math.ceil((s.blockedUntil - now) / 1000) };
      return { ok: true };
    },
    fail(ip, now = Date.now()) {
      failTimes.push(now);
      const s = perIp.get(ip) ?? { fails: 0, blockedUntil: 0 };
      s.fails += 1;
      if (s.fails >= REDEEM_IP_FAILS) {
        s.blockedUntil = now + REDEEM_IP_PAUSE_MS;
        s.fails = 0; // после паузы — снова 5 попыток
      }
      perIp.set(ip, s);
    },
    success(ip) {
      perIp.delete(ip);
    },
    globalBlockedAt(now = Date.now()) {
      return lastGlobalBlock !== null && now - lastGlobalBlock < REDEEM_GLOBAL_WINDOW_MS ? lastGlobalBlock : null;
    },
    reset() {
      perIp.clear();
      failTimes = [];
      lastGlobalBlock = null;
    },
  };
}

/** Один на процесс: маршрут и правило тревоги читают одно состояние. Тесты создают свой через createRedeemLimiter. */
export const redeemLimiter: RedeemLimiter = createRedeemLimiter();
