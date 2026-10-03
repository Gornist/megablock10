import type { NetService } from "./netService.js";

/**
 * Каркас «держать документы Моста в согласии с коллектором»: синк запускается при каждом (пере)подключении Моста и раз в
 * `intervalMs` (0 — таймер выключен, синк вызывают сами, как в тестах). Наследник пишет `sync()` и сам решает, что считать проходом.
 */
export abstract class PeriodicSync {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  /** Во время прохода кто-то снова вызвал sync(): после него нужен ещё один, иначе правка, пришедшая посреди записи, ждала бы таймера. */
  private again = false;
  lastError: string | null = null;

  protected constructor(
    protected readonly net: NetService,
    private readonly intervalMs: number,
  ) {}

  start(): void {
    if (!this.net.configured || this.timer) return;
    this.net.onConnected(() => void this.sync());
    if (this.intervalMs > 0) {
      this.timer = setInterval(() => void this.sync(), this.intervalMs);
      this.timer.unref();
    }
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  /**
   * Один проход за раз. Вызов во время прохода не запускает второй параллельно, а просит первый повторить (и возвращает `idle`).
   * Ошибка прохода не падает наружу: она в `lastError`, а повтор — по таймеру и при следующем подключении Моста.
   */
  protected async exclusive<T>(pass: () => Promise<T>, idle: T, add?: (total: T, next: T) => T, onError?: (e: unknown) => void): Promise<T> {
    if (!this.net.connected) return idle;
    if (this.running) {
      this.again = true;
      return idle;
    }
    this.running = true;
    let total = idle;
    try {
      do {
        this.again = false;
        const r = await pass();
        total = add ? add(total, r) : r;
      } while (this.again);
      this.lastError = null;
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : String(e);
      onError?.(e);
    } finally {
      this.running = false;
    }
    return total;
  }

  abstract sync(): Promise<unknown>;
}
