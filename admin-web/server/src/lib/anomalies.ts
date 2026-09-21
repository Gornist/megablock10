import type { AttentionItem, PulseSample } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { findFutureClocks } from "./integrity.js";
import { PULSE_INTERVAL_MS, readPulse } from "./pulse.js";

const MIN = 60_000;

/** Пороги детекторов пульса; правятся переменными окружения без пересборки. */
export function pulseThresholds() {
  const num = (v: string | undefined, d: number) => (v !== undefined && Number.isFinite(Number(v)) && Number(v) > 0 ? Number(v) : d);
  return {
    /** Онлайн упал ниже этой доли от недавнего пика — это не «игроки разошлись», а обрыв связи. */
    silenceRatio: num(process.env.ANOM_SILENCE_RATIO, 0.7),
    silenceMinPeak: num(process.env.ANOM_SILENCE_MIN_PEAK, 5),
    rejectMin: num(process.env.ANOM_REJECT_MIN, 10),
    rejectShare: num(process.env.ANOM_REJECT_SHARE, 0.3),
    slowAvgMs: num(process.env.ANOM_SLOW_MS, 500),
    clockAheadMs: num(process.env.ANOM_CLOCK_AHEAD_MIN, 5) * MIN,
  };
}

const REJECT_LABEL: Record<string, string> = {
  signature: "подпись не сходится (подделка или порча данных)",
  malformed: "битый формат записей",
  unknown: "неизвестные поля или причины (другая версия приложения?)",
  seq: "конфликт номеров записей (двойник устройства или сброс данных?)",
  actor: "чужой автор записи (подделка)",
  other: "прочее",
};

const sum = (xs: PulseSample[], f: (s: PulseSample) => number) => xs.reduce((a, s) => a + f(s), 0);

/**
 * Детекторы по пульсу игры (lib/pulse.ts). Без состояния: тревога живёт, пока условие держится на последних сэмплах, и сама гаснет,
 * когда оно проходит — этого достаточно вместо отдельного гистерезиса. «Два сэмпла подряд» защищает от разовых всплесков.
 * Если сэмплер давно молчит (нет свежих сэмплов) — тревог по пульсу нет: не о чем судить.
 */
export function computePulseAnomalies(db: Db, now = Date.now()): AttentionItem[] {
  const samples = readPulse(db, 15 * MIN, now);
  const last = samples[samples.length - 1];
  if (!last || now - last.t > 2.5 * PULSE_INTERVAL_MS) return [];

  const t = pulseThresholds();
  const items: AttentionItem[] = [];
  const recent = samples.slice(-3);

  // Массовое молчание: два последних сэмпла заметно ниже недавнего пика онлайна.
  const tail = samples.slice(-2);
  const before = samples.slice(0, -2);
  const peak = Math.max(0, ...before.map((s) => s.online));
  if (tail.length === 2 && peak >= t.silenceMinPeak && tail.every((s) => s.online <= peak * t.silenceRatio)) {
    items.push({
      id: "pulse:mass_silence",
      kind: "mass_silence",
      severity: "crit",
      title: "Массовая потеря связи",
      detail: `на связи ${last.online} из ${peak} недавних — сеть, точка доступа или сервер, а не игроки`,
      at: last.t,
    });
  }

  // Всплеск отклонений приёма.
  const rejected = sum(recent, (s) => s.rejected);
  const records = sum(recent, (s) => s.records);
  if (rejected >= t.rejectMin && rejected / (rejected + records) >= t.rejectShare) {
    const byCat: Record<string, number> = {};
    for (const s of recent) for (const [k, v] of Object.entries(s.rejectedBy)) byCat[k] = (byCat[k] ?? 0) + v;
    const top = Object.entries(byCat).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "other";
    items.push({
      id: "pulse:reject_spike",
      kind: "reject_spike",
      severity: top === "signature" || top === "actor" ? "crit" : "warn",
      title: "Сервер отклоняет много записей",
      detail: `${rejected} из ${rejected + records} за 3 мин; главная причина: ${REJECT_LABEL[top] ?? top}`,
      at: last.t,
    });
  }

  const limited = sum(recent, (s) => s.rateLimited);
  if (limited > 0) {
    items.push({ id: "pulse:rate_limited", kind: "rate_limited", severity: "warn", title: "Устройство упёрлось в лимит запросов", detail: `отклонено запросов: ${limited} за 3 мин (зациклившийся клиент или сбой сети)`, at: last.t });
  }

  const denied = sum(recent, (s) => s.secretDenied);
  if (denied >= 3) {
    items.push({ id: "pulse:secret_denied", kind: "secret_denied", severity: "warn", title: "Неверный секрет игры", detail: `отказов: ${denied} за 3 мин — у части телефонов другой секрет в Настройках`, at: last.t });
  }

  const requests = sum(recent, (s) => s.requests);
  const avg = requests ? sum(recent, (s) => s.latencyAvgMs * s.requests) / requests : 0;
  if (requests >= 10 && avg > t.slowAvgMs) {
    items.push({ id: "pulse:server_slow", kind: "server_slow", severity: "warn", title: "Сервер тормозит", detail: `среднее время приёма ${Math.round(avg)} мс за 3 мин (порог ${t.slowAvgMs})`, at: last.t });
  }

  return items;
}

/** Часы устройств, спешащие относительно сервера (за окно проверок целостности). */
export function computeClockAnomalies(db: Db, playerName: (key: string) => string, since: number): AttentionItem[] {
  const t = pulseThresholds();
  return findFutureClocks(db, since, t.clockAheadMs).map((c) => ({
    id: `clock:${c.subjectKey}`,
    kind: "clock_skew",
    severity: "warn",
    title: "Часы устройства спешат",
    detail: `${playerName(c.subjectKey)}: записи датированы на ${Math.round(c.aheadMs / MIN)} мин вперёд — сбитое время или подделка`,
    subjectKey: c.subjectKey,
    at: c.at,
  }));
}
