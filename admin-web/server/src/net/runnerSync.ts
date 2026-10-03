import type { Db } from "../db/index.js";
import { activePlayers, getPlayerBase } from "../lib/playerSummary.js";
import { bridgeRunnerDocId, createNetRunners, type NetRunnerAccess, type NetRunnerFlag, type NetRunners } from "../lib/netRunners.js";
import { BridgeUnavailableError, type BridgeDoc } from "./bridgeProtocol.js";
import type { NetService } from "./netService.js";

/**
 * Держит документы `runner` Моста в согласии с решениями мастера (docs/netrun-collector-brief.md): блокировка («пощадить», ручное закрытие
 * допуска), «может входить в Сеть» (`allowed`, белый список) и фракция персонажа (`faction`, её читает правило сигнала СБ).
 * Коллектор — источник правды: Мост ставит `runner.blocked` сам при black ICE как быструю защиту, а остальное приходит отсюда.
 *
 * Документ — `r_<sha256 ключа>`, сам ключ в `data.key`. Управляем только теми игроками, о ком мастер что-то решил (флаг блокировки или
 * отметка «нетраннер»): остальным документов не заводим, Мост создаст их сам при первом входе. Пока Моста нет, решения остаются
 * несинхронизированными (`bridge_synced = 0`) и догоняются при подключении, после действия мастера и раз в `NET_RUNNER_SYNC_MS`.
 */
export class RunnerSync {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private again = false;
  lastError: string | null = null;
  private readonly runners: NetRunners;

  constructor(
    private readonly db: Db,
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

  /** Сколько флагов блокировки ещё не доставлено в Мост. */
  pending(): number {
    return this.runners.unsynced().length;
  }

  /**
   * Сверить документы runner с решениями мастера. Возвращает, сколько документов реально записано. Параллельный вызов не запускает
   * второй проход, а просит первый пройти ещё раз (мастер мог нажать ещё одну кнопку, пока шла запись).
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
        written += await this.pass();
      } while (this.again);
      this.lastError = null;
    } catch (e) {
      // Мост пропал или отказал посреди прохода: остальное догонится при следующем подключении или по таймеру.
      this.lastError = e instanceof Error ? e.message : String(e);
      if (!(e instanceof BridgeUnavailableError)) console.warn(`[NET] документы runner не записаны в Мост: ${this.lastError}`);
    } finally {
      this.running = false;
    }
    return written;
  }

  private async pass(): Promise<number> {
    const flags = new Map(this.runners.list().map((f) => [f.runnerKey, f]));
    const access = new Map(this.runners.accessList().map((a) => [a.runnerKey, a]));
    const keys = new Set([...flags.keys(), ...access.keys()]);
    if (keys.size === 0) return 0;

    const players = new Map(activePlayers(getPlayerBase(this.db)).map((p) => [p.publicKeyB64, p]));
    const docs = new Map((await this.net.listDocs("runner")).map((d) => [d.id, d]));
    let written = 0;
    for (const key of keys) {
      const id = bridgeRunnerDocId(key);
      const player = players.get(key);
      const wrote = await this.push(key, docs.get(id) ?? null, flags.get(key), access.get(key), player ? { faction: player.faction || null, callsign: player.callsign || "" } : null);
      if (wrote) written++;
      const flag = flags.get(key);
      if (flag) this.runners.markSynced(key, flag.updatedAt);
    }
    return written;
  }

  private async push(key: string, cur: BridgeDoc | null, flag: NetRunnerFlag | undefined, access: NetRunnerAccess | undefined, player: { faction: string | null; callsign: string } | null): Promise<boolean> {
    // Документа нет, а писать нечего: нет блокировки, нет отметки «нетраннер» — Мост создаст runner сам при первом входе игрока.
    if (!cur && !flag?.blocked && !access?.allowed) return false;
    let wrote = false;
    await this.net.putDoc(
      "runner",
      bridgeRunnerDocId(key),
      (data) => {
        wrote = false;
        const next: Record<string, unknown> = {
          // Закрыть допуск заранее можно и тому, кого Мост ещё не знает: тогда документ с умолчаниями нового нетраннера (при входе Мост обновит callsign).
          ...(data ?? { callsign: player?.callsign ?? flag?.callsign ?? "", runs: 0, tutorial_done: false }),
          key,
        };
        if (flag) {
          next.blocked = flag.blocked;
          next.blocked_reason = flag.blocked ? flag.reason : null;
        } else if (next.blocked === undefined) {
          next.blocked = false;
        }
        if (access) next.allowed = access.allowed;
        else if (next.allowed === undefined) next.allowed = false;
        // Фракцию пишем только игроку, которого коллектор знает: чужого документа не стираем.
        if (player) next.faction = player.faction;
        if (data && JSON.stringify(sortKeys(data)) === JSON.stringify(sortKeys(next))) return null;
        wrote = true;
        return next;
      },
      4,
      cur,
    );
    return wrote;
  }
}

const sortKeys = (o: Record<string, unknown>) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)));
