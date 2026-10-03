import { positiveNumber } from "../lib/envNumber.js";
import type { BatteryThresholds } from "./battery.js";

/**
 * Настройки связи с точками: таймауты протокола, повторы, лимит соединений, опрос и пороги батареи. Значения по умолчанию
 * и переменные окружения DISPLAY_* (README, «Электронные дисплеи») — здесь, в одном месте; менеджер их только читает.
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

/** Пороги и окно оценки заряда (battery.ts) из настроек. */
export function batteryThresholds(c: Omit<DisplayManagerConfig, "log">): BatteryThresholds {
  return {
    lowMv: c.batteryLowMv,
    criticalMv: c.batteryCriticalMv,
    lowPct: c.batteryLowPct,
    criticalPct: c.batteryCriticalPct,
    lowHours: c.batteryLowHours,
    criticalHours: c.batteryCriticalHours,
    windowMs: c.batteryWindowMs,
  };
}
