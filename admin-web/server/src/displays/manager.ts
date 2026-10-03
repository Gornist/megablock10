import type { Socket } from "node:net";
import { estimateBattery, type BatteryEstimate } from "./battery.js";
import type { DisplayItem, DisplayPushOutcome, DisplayPushPhase, DisplayPushState, DisplayStatus } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { positiveNumber } from "../lib/envNumber.js";
import { DisplayFailure, DisplaySession, expectReply, type HelloInfo } from "./connection.js";
import { BacklightLevel, encodeBacklightPayload, encodeSecondsPayload, Format, MsgType, NackCode } from "./protocol.js";
import { renderQrForDisplay } from "./renderer.js";
import { DisplayRepository, parseRoles, secretKey, type DisplayRow } from "./repository.js";

/**
 * Единственный владелец связи с физическими дисплеями: очередь на каждый дисплей, общий лимит одновременных соединений,
 * повторы и таймауты, опрос «на связи ли». React сюда не ходит — только роуты (routes/displays.ts).
 *
 * Очередь на дисплей — «одна в работе + одна последняя ждущая» для картинок: e-paper обновляется секунды, поэтому 101 → 102 → 103
 * не показываются по очереди, а 102 заменяется на 103 ещё в очереди. Команды (тест, подсветка, перезагрузка) идут в той же
 * очереди по порядку — соединение с дисплеем в каждый момент одно.
 */

export interface DisplayManagerConfig {
  connectTimeoutMs: number;
  /** Сколько ждать HELLO (заголовок) после соединения. */
  helloTimeoutMs: number;
  /** Сколько ждать RECEIVED после отправки кадра: передача payload + проверка на дисплее. */
  receivedTimeoutMs: number;
  /** Сколько ждать DISPLAYED после RECEIVED: запись во flash + полное обновление e-paper. */
  displayedTimeoutMs: number;
  /** Ответ OK на команду (тест, подсветка, перезагрузка). */
  commandTimeoutMs: number;
  /** Паузы перед 2-й, 3-й… попыткой; попыток — длина + 1. */
  retryDelaysMs: number[];
  /** Одновременных TCP-соединений на все дисплеи. */
  maxConcurrent: number;
  /** Период опроса «на связи ли» (connect + HELLO); 0 — не опрашивать. */
  probeIntervalMs: number;
  /** Дисплей ONLINE, если подлинный HELLO был не раньше, чем столько назад. */
  onlineWindowMs: number;
  batteryLowMv: number;
  batteryCriticalMv: number;
  /** МАЛО / КРИТИЧНО по проценту и по остатку в часах (docs/sound-nodes.md, «Батарея»). */
  batteryLowPct: number;
  batteryCriticalPct: number;
  batteryLowHours: number;
  batteryCriticalHours: number;
  /** История заряда: точка не чаще раза в sampleMs, хранится keepMs, остаток — по последним windowMs. */
  batterySampleMs: number;
  batteryKeepMs: number;
  batteryWindowMs: number;
  log: (line: string) => void;
}

export const DEFAULT_DISPLAY_CONFIG: DisplayManagerConfig = {
  connectTimeoutMs: 2000,
  helloTimeoutMs: 2000,
  receivedTimeoutMs: 5000,
  displayedTimeoutMs: 10000,
  commandTimeoutMs: 5000,
  retryDelaysMs: [1000, 3000],
  maxConcurrent: 20,
  probeIntervalMs: 30000,
  onlineWindowMs: 75000,
  // Li-ion 21700: ниже 3,5 В остаётся немного, ниже 3,3 В — пора менять (без модели разряда — только пороги, не проценты).
  batteryLowMv: 3500,
  batteryCriticalMv: 3300,
  batteryLowPct: 25,
  batteryCriticalPct: 10,
  batteryLowHours: 12,
  batteryCriticalHours: 4,
  batterySampleMs: 5 * 60_000,
  batteryKeepMs: 4 * 24 * 3_600_000,
  batteryWindowMs: 2 * 3_600_000,
  log: (line) => console.log(line),
};

function retryDelays(raw: string | undefined, fallback: number[]): number[] {
  if (raw === undefined) return fallback;
  if (raw.trim() === "") return [];
  const parts = raw.split(",").map((s) => Number(s.trim()));
  return parts.every((n) => Number.isFinite(n) && n >= 0) ? parts : fallback;
}

/** Всё настраивается переменными окружения DISPLAY_* (README, «Электронные дисплеи»). */
export function displayConfigFromEnv(env: NodeJS.ProcessEnv = process.env): Omit<DisplayManagerConfig, "log"> {
  const d = DEFAULT_DISPLAY_CONFIG;
  const probe = env.DISPLAY_PROBE_INTERVAL_MS === "0" ? 0 : positiveNumber(env.DISPLAY_PROBE_INTERVAL_MS, d.probeIntervalMs);
  return {
    connectTimeoutMs: positiveNumber(env.DISPLAY_CONNECT_TIMEOUT_MS, d.connectTimeoutMs),
    helloTimeoutMs: positiveNumber(env.DISPLAY_HELLO_TIMEOUT_MS, d.helloTimeoutMs),
    receivedTimeoutMs: positiveNumber(env.DISPLAY_RECEIVED_TIMEOUT_MS, d.receivedTimeoutMs),
    displayedTimeoutMs: positiveNumber(env.DISPLAY_DISPLAYED_TIMEOUT_MS, d.displayedTimeoutMs),
    commandTimeoutMs: positiveNumber(env.DISPLAY_COMMAND_TIMEOUT_MS, d.commandTimeoutMs),
    retryDelaysMs: retryDelays(env.DISPLAY_RETRY_DELAYS_MS, d.retryDelaysMs),
    maxConcurrent: Math.floor(positiveNumber(env.DISPLAY_MAX_CONCURRENT, d.maxConcurrent)),
    probeIntervalMs: probe,
    onlineWindowMs: positiveNumber(env.DISPLAY_ONLINE_WINDOW_MS, probe > 0 ? Math.round(probe * 2.5) : d.onlineWindowMs),
    batteryLowMv: positiveNumber(env.DISPLAY_BATTERY_LOW_MV, d.batteryLowMv),
    batteryCriticalMv: positiveNumber(env.DISPLAY_BATTERY_CRITICAL_MV, d.batteryCriticalMv),
    batteryLowPct: positiveNumber(env.DISPLAY_BATTERY_LOW_PCT, d.batteryLowPct),
    batteryCriticalPct: positiveNumber(env.DISPLAY_BATTERY_CRITICAL_PCT, d.batteryCriticalPct),
    batteryLowHours: positiveNumber(env.DISPLAY_BATTERY_LOW_HOURS, d.batteryLowHours),
    batteryCriticalHours: positiveNumber(env.DISPLAY_BATTERY_CRITICAL_HOURS, d.batteryCriticalHours),
    batterySampleMs: positiveNumber(env.DISPLAY_BATTERY_SAMPLE_MS, d.batterySampleMs),
    batteryKeepMs: positiveNumber(env.DISPLAY_BATTERY_KEEP_MS, d.batteryKeepMs),
    batteryWindowMs: positiveNumber(env.DISPLAY_BATTERY_WINDOW_MS, d.batteryWindowMs),
  };
}

/** Заряд точки по её строке и истории — общее для DisplayItem и правила «Требует внимания» (lib/attentionRules). */
export function displayBattery(repo: DisplayRepository, row: DisplayRow, c: Omit<DisplayManagerConfig, "log">, now: number): BatteryEstimate {
  if (row.battery_mv === null && row.battery_pct === null) return { percent: null, hoursLeft: null, charging: false, level: null, source: null };
  const history = repo.batterySamples(row.id, now - Math.max(c.batteryWindowMs, 15 * 60_000));
  return estimateBattery(
    { mv: row.battery_mv, pct: row.battery_pct, rate: row.battery_rate, at: row.last_seen_at },
    history,
    {
      lowMv: c.batteryLowMv,
      criticalMv: c.batteryCriticalMv,
      lowPct: c.batteryLowPct,
      criticalPct: c.batteryCriticalPct,
      lowHours: c.batteryLowHours,
      criticalHours: c.batteryCriticalHours,
      windowMs: c.batteryWindowMs,
    },
    now,
  );
}

export interface OpResult {
  outcome: DisplayPushOutcome;
  version?: number;
  error?: string;
}

type CommandType = MsgType.TEST | MsgType.BACKLIGHT | MsgType.REBOOT;

type Op =
  | { kind: "image"; version: number; qr: string; label: string; sent: boolean; done: (r: OpResult) => void }
  | { kind: "command"; type: CommandType; payload: Buffer; done: (r: OpResult) => void }
  | { kind: "probe"; done: (r: OpResult) => void }
  | ({ kind: "custom"; done: (r: OpResult) => void } & CustomOp);

/**
 * Своя операция в очереди точки (звук — audio/audioService.ts): то же подключение, HELLO, лимит соединений и повторы, что у
 * картинок; run работает с открытой сессией. key — «последняя ждущая побеждает» (новое звуковое состояние заменяет старое в
 * очереди); front — вперёд очереди (объявление не ждёт смены фона). Статус точки UPDATING такие операции не включают.
 */
export interface CustomOp {
  name: string;
  key?: string;
  front?: boolean;
  /** Без DISPLAY_CONNECT/DISCONNECT в журнале — для частых служебных операций (как опрос). */
  quiet?: boolean;
  run: (session: DisplaySession, row: DisplayRow) => Promise<OpResult>;
}

/** Вызывается на каждом подлинном HELLO (и опросе): звук сверяет доложенное с желаемым. */
export type HelloHook = (row: DisplayRow, hello: HelloInfo) => void;

interface Worker {
  queue: Op[];
  active: Op | null;
}

/** Счётный семафор: не больше N одновременных сессий на все дисплеи; ждущие — по очереди. */
class Semaphore {
  private free: number;
  private readonly waiting: (() => void)[] = [];
  constructor(n: number) {
    this.free = Math.max(1, n);
  }
  async acquire(): Promise<() => void> {
    if (this.free > 0) this.free--;
    else await new Promise<void>((resolve) => this.waiting.push(resolve));
    let released = false;
    return () => {
      if (released) return;
      released = true;
      const next = this.waiting.shift();
      if (next) next();
      else this.free++;
    };
  }
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export const BACKLIGHT_LEVELS: Record<string, BacklightLevel> = { OFF: BacklightLevel.OFF, LOW: BacklightLevel.LOW, MEDIUM: BacklightLevel.MEDIUM, HIGH: BacklightLevel.HIGH };

export class DisplayManager {
  readonly repo: DisplayRepository;
  readonly config: DisplayManagerConfig;
  private readonly workers = new Map<string, Worker>();
  private readonly helloHooks: HelloHook[] = [];
  /** Звуковая часть карточки (audio/audioService.ts); без неё — null. */
  private audioView: ((row: DisplayRow) => DisplayItem["audio"]) | null = null;
  /** Ход последней отправки картинки на каждый дисплей — для экрана (DisplayItem.push); только в памяти. */
  private readonly progress = new Map<string, DisplayPushState>();
  private readonly semaphore: Semaphore;
  private readonly sockets = new Set<Socket>();
  private probeTimer: NodeJS.Timeout | null = null;
  /** Итог последнего опроса по дисплею — в журнал идёт только смена «на связи ↔ нет связи», а не каждый опрос. */
  private readonly reachable = new Map<string, boolean>();
  private stopped = false;

  constructor(db: Db, config: Partial<DisplayManagerConfig> = {}) {
    this.repo = new DisplayRepository(db);
    this.config = { ...DEFAULT_DISPLAY_CONFIG, ...config };
    this.semaphore = new Semaphore(this.config.maxConcurrent);
  }

  // ── Состояние для API ──

  toItem(row: DisplayRow, now = Date.now()): DisplayItem {
    const w = this.workers.get(row.id);
    const activeImage = w?.active?.kind === "image" ? w.active : null;
    const pendingImage = w?.queue.find((op): op is Extract<Op, { kind: "image" }> => op.kind === "image") ?? null;
    let status: DisplayStatus;
    if (!row.enabled) status = "DISABLED";
    else if ([w?.active, ...(w?.queue ?? [])].some((op) => op && op.kind !== "probe" && op.kind !== "custom")) status = "UPDATING";
    else if (row.last_error) status = "ERROR";
    else if (row.last_seen_at !== null && now - row.last_seen_at <= this.config.onlineWindowMs) status = "ONLINE";
    else status = "OFFLINE";
    const bat = this.batteryOf(row, now);
    return {
      id: row.id,
      name: row.name,
      ip: row.ip,
      port: row.port,
      width: row.width,
      height: row.height,
      enabled: row.enabled === 1,
      groupId: row.group_id,
      nodeId: row.node_id,
      status,
      hardwareId: row.hardware_id,
      fwVersion: row.fw_version,
      batteryMv: row.battery_mv,
      battery: bat.level,
      batteryPct: bat.percent,
      batterySource: bat.source,
      batteryHoursLeft: bat.hoursLeft,
      batteryCharging: bat.charging,
      rssi: row.rssi,
      lastSeenAt: row.last_seen_at,
      lastConnectedAt: row.last_connected_at,
      lastError: row.last_error,
      lastErrorAt: row.last_error_at,
      desiredVersion: row.desired_version > 0 ? row.desired_version : null,
      desiredLabel: row.desired_label,
      displayedVersion: row.displayed_version,
      displayedAt: row.displayed_at,
      activeVersion: activeImage?.version ?? null,
      pendingVersion: pendingImage?.version ?? null,
      push: this.progress.get(row.id) ?? null,
      roles: parseRoles(row.roles),
      audio: this.audioView ? this.audioView(row) : null,
    };
  }

  /** Заряд для экрана: процент (топливомер или по напряжению), остаток по истории, уровень по порогам. */
  batteryOf(row: DisplayRow, now = Date.now()): BatteryEstimate {
    return displayBattery(this.repo, row, this.config, now);
  }

  list(): DisplayItem[] {
    const now = Date.now();
    return this.repo.list().map((r) => this.toItem(r, now));
  }

  get(id: string): DisplayItem | null {
    const row = this.repo.get(id);
    return row ? this.toItem(row) : null;
  }

  // ── Постановка в очередь ──

  /**
   * Новая картинка на дисплей. Версия назначается сразу (и сохраняется как «что должно быть на экране»), промис — итог
   * именно этой версии: DISPLAYED, FAILED или SUPERSEDED (в очереди её обогнала более новая).
   */
  pushImage(displayId: string, qr: string, label: string): { version: number; result: Promise<OpResult> } {
    const version = this.repo.assignDesired(displayId, qr, label);
    return { version, result: this.enqueueImage(displayId, version, qr, label) };
  }

  private enqueueImage(displayId: string, version: number, qr: string, label: string): Promise<OpResult> {
    return new Promise<OpResult>((done) => {
      const w = this.worker(displayId);
      const now = Date.now();
      this.progress.set(displayId, {
        version,
        label,
        phase: "QUEUED",
        attempt: 0,
        attempts: this.config.retryDelaysMs.length + 1,
        startedAt: now,
        updatedAt: now,
        error: null,
        failedAt: null,
        retryAt: null,
      });
      const op: Op = { kind: "image", version, qr, label, sent: false, done };
      const pending = w.queue.findIndex((o) => o.kind === "image");
      if (pending >= 0) {
        const old = w.queue[pending] as Extract<Op, { kind: "image" }>;
        this.log("DISPLAY_SUPERSEDED", displayId, `image=${old.version} by=${version}`);
        old.done({ outcome: "SUPERSEDED", version: old.version });
        w.queue[pending] = op;
      } else {
        w.queue.push(op);
      }
      this.kick(displayId);
    });
  }

  /** Своя операция (см. CustomOp). */
  enqueueCustom(displayId: string, op: CustomOp): Promise<OpResult> {
    return new Promise<OpResult>((done) => {
      const w = this.worker(displayId);
      const item: Op = { kind: "custom", ...op, done };
      if (op.key) {
        const i = w.queue.findIndex((o) => o.kind === "custom" && o.key === op.key);
        if (i >= 0) {
          w.queue[i].done({ outcome: "SUPERSEDED" });
          w.queue.splice(i, 1);
        }
      }
      if (op.front) w.queue.unshift(item);
      else w.queue.push(item);
      this.kick(displayId);
    });
  }

  /**
   * Есть ли в очереди точки (или в работе) своя операция с этим ключом — чтобы не ставить вторую такую же. queuedOnly —
   * только ждущие: операция в работе уже прочитала строку, и новое желаемое она не отправит.
   */
  hasCustom(displayId: string, key: string, queuedOnly = false): boolean {
    const w = this.workers.get(displayId);
    return !!w && [queuedOnly ? undefined : w.active, ...w.queue].some((o) => o?.kind === "custom" && o.key === key);
  }

  onHello(hook: HelloHook): void {
    this.helloHooks.push(hook);
  }

  setAudioView(view: (row: DisplayRow) => DisplayItem["audio"]): void {
    this.audioView = view;
  }

  command(displayId: string, type: CommandType, payload: Buffer): Promise<OpResult> {
    return new Promise<OpResult>((done) => {
      this.worker(displayId).queue.push({ kind: "command", type, payload, done });
      this.kick(displayId);
    });
  }

  test(displayId: string, seconds = 30): Promise<OpResult> {
    return this.command(displayId, MsgType.TEST, encodeSecondsPayload(seconds));
  }

  backlight(displayId: string, level: BacklightLevel, seconds = 0): Promise<OpResult> {
    return this.command(displayId, MsgType.BACKLIGHT, encodeBacklightPayload(level, seconds));
  }

  reboot(displayId: string): Promise<OpResult> {
    return this.command(displayId, MsgType.REBOOT, Buffer.alloc(0));
  }

  /** Разовый опрос (connect + HELLO) — только если дисплею сейчас ничего не отправляется. */
  probe(displayId: string): Promise<OpResult> | null {
    const w = this.worker(displayId);
    if (w.active || w.queue.length > 0) return null;
    return new Promise<OpResult>((done) => {
      w.queue.push({ kind: "probe", done });
      this.kick(displayId);
    });
  }

  /** Дисплей удалён: ждущее в очереди отменяется (текущая попытка доработает и увидит, что записи нет). */
  forget(displayId: string): void {
    const w = this.workers.get(displayId);
    if (!w) return;
    for (const op of w.queue.splice(0)) op.done({ outcome: "FAILED", error: "display removed" });
    this.progress.delete(displayId);
  }

  startProbing(): void {
    if (this.config.probeIntervalMs <= 0 || this.probeTimer) return;
    this.probeTimer = setInterval(() => this.probeAll(), this.config.probeIntervalMs);
    this.probeTimer.unref();
    this.probeAll();
  }

  probeAll(): Promise<unknown> {
    return Promise.all(this.repo.list().filter((r) => r.enabled).map((r) => this.probe(r.id)));
  }

  stop(): void {
    this.stopped = true;
    if (this.probeTimer) clearInterval(this.probeTimer);
    this.probeTimer = null;
    for (const w of this.workers.values()) for (const op of w.queue.splice(0)) op.done({ outcome: "FAILED", error: "server stopping" });
    for (const s of this.sockets) s.destroy();
  }

  /** Ждать, пока очередь дисплея опустеет (тесты). */
  async idle(displayId?: string): Promise<void> {
    const busy = () => [...this.workers.entries()].some(([id, w]) => (displayId === undefined || id === displayId) && (w.active || w.queue.length > 0));
    while (busy()) await sleep(5);
  }

  // ── Исполнение ──

  private worker(displayId: string): Worker {
    let w = this.workers.get(displayId);
    if (!w) {
      w = { queue: [], active: null };
      this.workers.set(displayId, w);
    }
    return w;
  }

  private kick(displayId: string): void {
    const w = this.worker(displayId);
    if (w.active) return;
    const op = w.queue.shift();
    if (!op) return;
    w.active = op;
    this.run(displayId, op)
      .catch((err) => ({ outcome: "FAILED" as const, error: String(err) }))
      .then((result) => {
        w.active = null;
        op.done(result);
        this.kick(displayId);
      });
  }

  private async run(displayId: string, op: Op): Promise<OpResult> {
    const result = await this.runAttempts(displayId, op);
    if (op.kind === "image") {
      const phase = result.outcome === "DISPLAYED" ? "DISPLAYED" : result.outcome === "SUPERSEDED" ? "SUPERSEDED" : "FAILED";
      this.setPhase(displayId, op, phase, { error: phase === "FAILED" ? (result.error ?? "failed") : null, retryAt: null });
    }
    if (op.kind === "probe") {
      const up = result.outcome === "DISPLAYED";
      if (this.reachable.get(displayId) !== up) this.log(up ? "DISPLAY_ONLINE" : "DISPLAY_OFFLINE", displayId, up ? "" : (result.error ?? ""));
      this.reachable.set(displayId, up);
    }
    return result;
  }

  private async runAttempts(displayId: string, op: Op): Promise<OpResult> {
    const attempts = op.kind === "probe" ? 1 : this.config.retryDelaysMs.length + 1;
    let last: DisplayFailure | null = null;
    for (let attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await sleep(this.config.retryDelaysMs[attempt - 1]);
        // Пока ждали повтора, пришла картинка новее — эту уже не показывать.
        if (op.kind === "image" && this.worker(displayId).queue.some((o) => o.kind === "image")) {
          return { outcome: "SUPERSEDED", version: op.version };
        }
      }
      if (this.stopped) return { outcome: "FAILED", error: "server stopping" };
      const row = this.repo.get(displayId);
      if (!row) return { outcome: "FAILED", error: "display removed" };
      if (!row.enabled) return { outcome: "FAILED", error: "display is disabled" };
      const release = await this.semaphore.acquire();
      try {
        if (op.kind === "image") this.setPhase(displayId, op, "CONNECTING", { attempt: attempt + 1, retryAt: null });
        return await this.attempt(row, op);
      } catch (err) {
        last = err instanceof DisplayFailure ? err : new DisplayFailure("PROTOCOL", String(err), false);
        // Опрос недоступного дисплея — обычное OFFLINE раз в 30 с на каждый выключенный; в журнал только то, что требует рук.
        if (op.kind !== "probe" || !last.retryable) this.logFailure(displayId, op, last, attempt + 1);
        if (op.kind === "image" && last.retryable && attempt + 1 < attempts) {
          this.setPhase(displayId, op, "RETRY", { error: last.summary, retryAt: Date.now() + this.config.retryDelaysMs[attempt] });
        }
        if (!last.retryable) break;
      } finally {
        release();
      }
    }
    const error = last?.summary ?? "failed";
    // Недоступность при опросе — это OFFLINE (видно по last_seen), а не ошибка; неверный секрет или чужое устройство — ошибка.
    if (op.kind !== "probe" || (last && !last.retryable)) this.repo.setError(displayId, error, Date.now());
    return { outcome: "FAILED", version: op.kind === "image" ? op.version : undefined, error };
  }

  private async attempt(row: DisplayRow, op: Op): Promise<OpResult> {
    const session = await DisplaySession.open(
      { host: row.ip, port: row.port, deviceId: row.id, key: secretKey(row) },
      { connectMs: this.config.connectTimeoutMs, helloMs: this.config.helloTimeoutMs },
      (socket) => {
        this.sockets.add(socket);
        return () => this.sockets.delete(socket);
      },
    );
    const now = Date.now();
    const hello = session.hello;
    const quiet = op.kind === "probe" || (op.kind === "custom" && op.quiet === true);
    if (!quiet) this.log("DISPLAY_CONNECT", row.id, `ip=${row.ip}:${row.port} shows=${hello.displayedVersion} fw=${hello.status.fw ?? "?"}`);
    try {
      this.repo.markSeen(row.id, now, {
        hardwareId: hello.status.hw,
        fw: hello.status.fw,
        batteryMv: hello.status.batteryMv,
        batteryPct: hello.status.batteryPct,
        batteryRate: hello.status.batteryRate,
        rssi: hello.status.rssi,
        displayedVersion: hello.displayedVersion,
      });
      this.repo.setRoles(row.id, hello.status.roles, hello.status.audio);
      const seen = this.repo.get(row.id);
      if (seen) this.repo.recordBattery(row.id, now, seen.battery_mv, seen.battery_pct, this.config.batterySampleMs, this.config.batteryKeepMs);
      if (seen) for (const hook of this.helloHooks) hook(seen, hello);
      if (hello.width !== row.width || hello.height !== row.height) {
        throw new DisplayFailure("CONFIG", `panel is ${hello.width}×${hello.height}, display record says ${row.width}×${row.height}`, false, NackCode.BAD_FORMAT);
      }
      if (op.kind === "probe") return this.afterProbe(row, hello.displayedVersion);
      if (op.kind === "command") return await this.sendCommand(session, row, op);
      if (op.kind === "custom") {
        this.log("DISPLAY_OP", row.id, op.name);
        return await op.run(session, this.repo.get(row.id) ?? row);
      }
      return await this.sendImage(session, row, op, hello.displayedVersion);
    } finally {
      await session.close();
      if (!quiet) this.log("DISPLAY_DISCONNECT", row.id, "");
    }
  }

  private afterProbe(row: DisplayRow, displayed: number): OpResult {
    if (displayed > row.desired_version) {
      // Дисплей показывает то, чего сервер не отправлял на своей памяти (БД восстановили из копии) — не затирать молча.
      this.repo.bumpDesiredVersion(row.id, displayed);
      if (row.desired_version > 0) {
        this.repo.setError(row.id, `display shows version ${displayed}, newer than the server knows (${row.desired_version}) — database restored? Send the QR again`, Date.now());
      }
    } else if (displayed < row.desired_version && row.desired_qr) {
      // Отправка не дошла (дисплей был вне сети) — связь вернулась, досылаем то, что должно быть на экране, той же версией.
      this.log("DISPLAY_RESYNC", row.id, `shows=${displayed} desired=${row.desired_version}`);
      void this.enqueueImage(row.id, row.desired_version, row.desired_qr, row.desired_label ?? "");
    } else if (row.last_error) {
      this.repo.clearError(row.id);
    }
    return { outcome: "DISPLAYED", version: displayed };
  }

  private async sendCommand(session: DisplaySession, row: DisplayRow, op: Extract<Op, { kind: "command" }>): Promise<OpResult> {
    const name = MsgType[op.type];
    this.log("DISPLAY_COMMAND", row.id, `cmd=${name}`);
    await session.request({ type: op.type, payload: op.payload }, this.config.commandTimeoutMs);
    this.log("DISPLAY_COMMAND_OK", row.id, `cmd=${name}`);
    return { outcome: "DISPLAYED" };
  }

  private async sendImage(session: DisplaySession, row: DisplayRow, op: Extract<Op, { kind: "image" }>, displayed: number): Promise<OpResult> {
    if (displayed >= op.version) {
      if (displayed === op.version && op.sent) {
        // Прошлая попытка дошла до экрана, но DISPLAYED потерялся по дороге.
        this.repo.markDisplayed(row.id, op.version, Date.now());
        this.setPhase(row.id, op, "DISPLAYED");
        this.log("DISPLAY_DISPLAYED", row.id, `image=${op.version} (confirmed by HELLO)`);
        return { outcome: "DISPLAYED", version: op.version };
      }
      this.renumber(row.id, op, displayed);
    }
    const bitmap = renderQrForDisplay(op.qr, row.width, row.height);
    this.setPhase(row.id, op, "SENDING");
    this.log("DISPLAY_SEND_START", row.id, `image=${op.version} bytes=${bitmap.data.length}`);
    session.send({ type: MsgType.IMAGE, seq: op.version, width: bitmap.width, height: bitmap.height, format: Format.BPP1, payload: bitmap.data });
    op.sent = true;
    try {
      const received = expectReply(await session.next(this.config.receivedTimeoutMs, "RECEIVED"), MsgType.RECEIVED, "RECEIVED");
      this.setPhase(row.id, op, "RECEIVED");
      this.log("DISPLAY_RECEIVED", row.id, `image=${received.header.seq}`);
      const shown = expectReply(await session.next(this.config.displayedTimeoutMs, "DISPLAYED"), MsgType.DISPLAYED, "DISPLAYED");
      this.repo.markDisplayed(row.id, shown.header.seq, Date.now());
      this.setPhase(row.id, op, "DISPLAYED");
      this.log("DISPLAY_DISPLAYED", row.id, `image=${shown.header.seq}`);
      return { outcome: "DISPLAYED", version: op.version };
    } catch (err) {
      if (err instanceof DisplayFailure && err.nack === NackCode.STALE_VERSION && err.displayedVersion !== undefined) {
        // Между HELLO и кадром дисплей успел показать что-то новее — следующая попытка уйдёт с версией выше.
        this.renumber(row.id, op, err.displayedVersion);
        throw new DisplayFailure("NACK", err.message, true, err.nack, err.displayedVersion);
      }
      throw err;
    }
  }

  private renumber(displayId: string, op: Extract<Op, { kind: "image" }>, displayed: number): void {
    const version = displayed + 1;
    this.log("DISPLAY_RENUMBER", displayId, `image=${op.version} -> ${version} (display shows ${displayed})`);
    const p = this.progress.get(displayId);
    if (p && p.version === op.version) p.version = version;
    op.version = version;
    op.sent = false;
    this.repo.bumpDesiredVersion(displayId, version);
  }

  private logFailure(displayId: string, op: Op, f: DisplayFailure, attempt: number): void {
    const event =
      f.nack === NackCode.AUTH_FAILED || f.kind === "AUTH"
        ? "DISPLAY_AUTH_FAILED"
        : f.nack === NackCode.BAD_CRC || f.kind === "CRC"
          ? "DISPLAY_CRC_FAILED"
          : f.kind === "TIMEOUT"
            ? "DISPLAY_TIMEOUT"
            : "DISPLAY_ERROR";
    const what = op.kind === "image" ? `image=${op.version}` : op.kind === "command" ? `cmd=${MsgType[op.type]}` : op.kind === "custom" ? `op=${op.name}` : "probe";
    this.log(event, displayId, `${what} attempt=${attempt} retryable=${f.retryable} ${f.summary}`);
  }

  /** Этап отправки для экрана — только если это та же отправка (новая картинка уже заняла место — её не трогать). */
  private setPhase(displayId: string, op: Extract<Op, { kind: "image" }>, phase: DisplayPushPhase, patch: Partial<DisplayPushState> = {}): void {
    const p = this.progress.get(displayId);
    if (!p || p.version !== op.version) return;
    if ((phase === "RETRY" || phase === "FAILED") && p.phase !== "RETRY" && p.phase !== "FAILED") p.failedAt = p.phase;
    // Причина прошлой попытки остаётся видна, пока идёт следующая («попытка 2 из 3: нет ответа»); успех её стирает.
    Object.assign(p, patch, { phase, updatedAt: Date.now() }, phase === "DISPLAYED" ? { error: null, failedAt: null } : {});
  }

  private log(event: string, displayId: string, details: string): void {
    this.config.log(`[DISPLAY] ${event} ${displayId}${details ? ` ${details}` : ""}`);
  }
}
