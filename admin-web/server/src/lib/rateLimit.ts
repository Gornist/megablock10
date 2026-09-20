/**
 * Простой rate-limit по ключу (IP) в памяти процесса — коллектор
 * однопроцессный, персистентность между рестартами не нужна. Единственное
 * применения — POST /api/auth/login (дашборд висит в открытой игровой сети, §9 ТЗ, и без лимита
 * мастерский токен можно подбирать перебором) и POST /api/changes (защита от зациклившегося клиента).
 */
export class RateLimiter {
  private hits = new Map<string, number[]>();

  constructor(
    private readonly max: number,
    private readonly windowMs: number,
  ) {}

  /** true — лимит превышен, запрос стоит отклонить. Сам факт вызова считается попыткой. */
  hit(key: string): boolean {
    const now = Date.now();
    const timestamps = (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
    timestamps.push(now);
    this.hits.set(key, timestamps);
    // Адреса, которые давно молчат, иначе оставались бы в карте навсегда.
    if (this.hits.size > 1000) {
      for (const [k, ts] of this.hits) if (ts.every((t) => now - t >= this.windowMs)) this.hits.delete(k);
    }
    return timestamps.length > this.max;
  }

  /** Сбросить счётчик при успешном входе — свои же неудачные попытки (опечатка в токене) не должны запирать мастера на весь windowMs после того, как он всё же ввёл верно. */
  reset(key: string): void {
    this.hits.delete(key);
  }
}
