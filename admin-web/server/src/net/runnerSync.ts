import type { Db } from "../db/index.js";
import { createNetRunners, toBridgeRunnerKey, type NetRunnerFlag, type NetRunners } from "../lib/netRunners.js";
import { BridgeUnavailableError } from "./bridgeProtocol.js";
import type { NetService } from "./netService.js";

/**
 * Доставляет решения мастера о допуске в документы `runner` Моста (docs/netrun-collector-brief.md, «пощадить»). Коллектор — источник
 * правды: Мост ставит `runner.blocked` сам при black ICE как быструю защиту, а «пощадить» и ручное закрытие допуска приходят отсюда.
 * Пока Моста нет, флаги остаются несинхронизированными (`bridge_synced = 0`) и догоняются при подключении и по таймеру.
 */
export class RunnerSync {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private again = false;
  lastError: string | null = null;
  private readonly runners: NetRunners;

  constructor(
    db: Db,
    private readonly net: NetService,
    private readonly intervalMs = Number(process.env.NET_RUNNER_SYNC_MS ?? 30_000),
  ) {
    this.runners = createNetRunners(db);
  }

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

  /** Сколько флагов ещё не доставлено в Мост. */
  pending(): number {
    return this.runners.unsynced().length;
  }

  /**
   * Записать в Мост все недоставленные флаги. Возвращает, сколько документов `runner` реально изменено. Параллельный вызов не
   * запускает второй проход, а просит первый пройти ещё раз (мастер мог нажать ещё одну кнопку, пока шла запись).
   */
  async sync(): Promise<number> {
    if (!this.net.connected) return 0;
    if (this.running) {
      this.again = true;
      return 0;
    }
    this.running = true;
    let written = 0;
    try {
      do {
        this.again = false;
        for (const flag of this.runners.unsynced()) {
          if (await this.push(flag)) written++;
        }
      } while (this.again);
      this.lastError = null;
    } catch (e) {
      // Мост пропал или отказал посреди прохода: остальные флаги догонятся при следующем подключении или по таймеру.
      this.lastError = e instanceof Error ? e.message : String(e);
      if (!(e instanceof BridgeUnavailableError)) console.warn(`[NET] флаг допуска не записан в Мост: ${this.lastError}`);
    } finally {
      this.running = false;
    }
    return written;
  }

  private async push(flag: NetRunnerFlag): Promise<boolean> {
    let wrote = false;
    await this.net.putDoc("runner", toBridgeRunnerKey(flag.runnerKey), (cur) => {
      const blocked = cur?.blocked === true;
      // Документа нет, а снимать нечего — писать незачем: Мост создаст runner сам при первом входе игрока.
      if (!cur && !flag.blocked) return null;
      if (cur && blocked === flag.blocked && (cur.blocked_reason ?? null) === (flag.blocked ? flag.reason : null)) return null;
      wrote = true;
      return {
        // Закрыть допуск заранее можно и тому, кого Мост ещё не знает: тогда создаём документ с теми же умолчаниями, что у нового нетраннера.
        ...(cur ?? { callsign: flag.callsign ?? "", runs: 0, tutorial_done: false }),
        blocked: flag.blocked,
        blocked_reason: flag.blocked ? flag.reason : null,
      };
    });
    this.runners.markSynced(flag.runnerKey, flag.updatedAt);
    return wrote;
  }
}
