import type { NetService } from "./netService.js";

/**
 * Каркас «держать документы Моста в согласии с коллектором»: синк запускается при каждом (пере)подключении Моста и раз в
 * `intervalMs` (0 — таймер выключен, синк вызывают сами, как в тестах). Наследник пишет `sync()` и сам решает, что считать проходом.
 */
export abstract class PeriodicSync {
  private timer: NodeJS.Timeout | null = null;
  /** Идёт проход синка. */
  protected running = false;
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

  abstract sync(): Promise<unknown>;
}
