import type { BatteryLevel } from "../apiTypes.js";
import { batteryThresholds, type DisplayManagerConfig } from "./config.js";
import type { DisplayRepository, DisplayRow } from "./repository.js";

/**
 * Заряд точки (дисплей, звуковая точка) для коллектора — docs/sound-nodes.md, «Батарея». Точка шлёт в HELLO милливольты и,
 * если впаян топливомер MAX17048, процент и скорость разряда. Здесь: процент по напряжению (если топливомера нет), оценка
 * «сколько часов осталось» по истории заряда и уровень НОРМА / МАЛО / КРИТИЧНО.
 */

/** Типичная кривая Li-ion 21700 без нагрузки, по убыванию — та же таблица в прошивке (firmware/display/lib/core/src/battery.cpp). */
export const LIION_CURVE: readonly (readonly [mv: number, pct: number])[] = [
  [4200, 100], [4150, 95], [4110, 90], [4080, 85], [4020, 80], [3980, 75], [3950, 70], [3910, 65], [3870, 60], [3850, 55],
  [3840, 50], [3820, 45], [3800, 40], [3790, 35], [3770, 30], [3750, 25], [3730, 20], [3710, 15], [3690, 10], [3610, 5], [3270, 0],
];

export function percentFromMilliVolts(mv: number): number {
  if (mv >= LIION_CURVE[0][0]) return 100;
  const last = LIION_CURVE[LIION_CURVE.length - 1];
  if (mv <= last[0]) return 0;
  for (let i = 1; i < LIION_CURVE.length; i++) {
    const [loMv, loPct] = LIION_CURVE[i];
    if (mv >= loMv) {
      const [hiMv, hiPct] = LIION_CURVE[i - 1];
      return Math.round(loPct + ((mv - loMv) * (hiPct - loPct)) / (hiMv - loMv));
    }
  }
  return 0;
}

export interface BatterySample {
  at: number;
  mv: number | null;
  pct: number | null;
}

export interface BatteryThresholds {
  lowMv: number;
  criticalMv: number;
  lowPct: number;
  criticalPct: number;
  lowHours: number;
  criticalHours: number;
  /** За какое время брать историю для оценки остатка. */
  windowMs: number;
}

export interface BatteryEstimate {
  /** 0…100; null — точка не шлёт заряд. */
  percent: number | null;
  /** «Примерно сколько часов осталось»; null — не разряжается заметно или истории мало. */
  hoursLeft: number | null;
  charging: boolean;
  level: BatteryLevel | null;
  /** gauge — процент от топливомера; voltage — посчитан по напряжению (грубее, под нагрузкой проседает). */
  source: "gauge" | "voltage" | null;
}

const HOUR = 3_600_000;
/** Без топливомера процент — по медиане напряжения за столько последних мс: под нагрузкой (звук) оно прыгает. */
const VOLTAGE_MEDIAN_MS = 15 * 60_000;

/** Процент точки истории: от топливомера, иначе по напряжению. */
const pctOf = (s: BatterySample): number | null => s.pct ?? (s.mv !== null ? percentFromMilliVolts(s.mv) : null);

/** Наклон МНК, % в час; null — точек мало или они слишком близко по времени (шум вместо тренда). */
export function dischargeRate(points: { at: number; pct: number }[], minSpanMs: number): number | null {
  if (points.length < 3) return null;
  const t0 = points[0].at;
  const xs = points.map((p) => (p.at - t0) / HOUR);
  if (xs[xs.length - 1] - xs[0] < minSpanMs / HOUR) return null;
  const n = points.length;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = points.reduce((a, p) => a + p.pct, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i++) {
    num += (xs[i] - mx) * (points[i].pct - my);
    den += (xs[i] - mx) ** 2;
  }
  return den > 0 ? num / den : null;
}

/**
 * current — из последнего HELLO; history — точки за последние сутки-двое (по возрастанию времени), current может в неё не входить.
 * rate — скорость от топливомера (% в час, минус — разряд): ею оценка пользуется, пока своей истории мало (сразу после запуска).
 */
export function estimateBattery(
  current: { mv: number | null; pct: number | null; rate: number | null; at: number | null },
  history: BatterySample[],
  t: BatteryThresholds,
  now: number,
): BatteryEstimate {
  const gauge = current.pct !== null;
  let percent: number | null = current.pct;
  if (percent === null && current.mv !== null) {
    // Без топливомера напряжение под нагрузкой (звук) прыгает — медиана за последние 15 минут.
    const recent = history.filter((s) => s.mv !== null && s.at >= now - VOLTAGE_MEDIAN_MS).map((s) => s.mv!);
    recent.push(current.mv);
    recent.sort((a, b) => a - b);
    percent = percentFromMilliVolts(recent[Math.floor(recent.length / 2)]);
  }
  if (percent === null) return { percent: null, hoursLeft: null, charging: false, level: null, source: null };

  const points = history
    .filter((s) => s.at >= now - t.windowMs)
    .map((s) => ({ at: s.at, pct: pctOf(s) }))
    .filter((p): p is { at: number; pct: number } => p.pct !== null);
  if (current.at !== null && !points.some((p) => p.at === current.at)) points.push({ at: current.at, pct: percent });
  points.sort((a, b) => a.at - b.at);
  let slope = dischargeRate(points, t.windowMs / 4);
  if (slope === null && current.rate !== null) slope = current.rate;

  const charging = slope !== null && slope > 0.5;
  // Меньше 0,1 %/ч — точка фактически не разряжается (или шум): остаток не выдумываем.
  const hoursLeft = slope !== null && slope < -0.1 ? Math.min(999, percent / -slope) : null;

  let level: BatteryLevel = "OK";
  // Порог по напряжению — только без топливомера: под громкой музыкой оно проседает, а процент топливомера это учитывает.
  const mvLow = !gauge && current.mv !== null ? current.mv : null;
  if (percent <= t.criticalPct || (hoursLeft !== null && hoursLeft < t.criticalHours) || (mvLow !== null && mvLow <= t.criticalMv)) {
    level = "CRITICAL";
  } else if (percent <= t.lowPct || (hoursLeft !== null && hoursLeft < t.lowHours) || (mvLow !== null && mvLow <= t.lowMv)) {
    level = "LOW";
  }
  return { percent, hoursLeft: hoursLeft === null ? null : Math.round(hoursLeft * 10) / 10, charging, level, source: gauge ? "gauge" : "voltage" };
}

/** Заряд точки по её строке и истории — общее для DisplayItem и правила «Требует внимания» (lib/attentionRules). */
export function displayBattery(repo: DisplayRepository, row: DisplayRow, c: Omit<DisplayManagerConfig, "log">, now: number): BatteryEstimate {
  if (row.battery_mv === null && row.battery_pct === null) return { percent: null, hoursLeft: null, charging: false, level: null, source: null };
  const history = repo.batterySamples(row.id, now - Math.max(c.batteryWindowMs, VOLTAGE_MEDIAN_MS));
  return estimateBattery(
    { mv: row.battery_mv, pct: row.battery_pct, rate: row.battery_rate, at: row.last_seen_at },
    history,
    batteryThresholds(c),
    now,
  );
}
