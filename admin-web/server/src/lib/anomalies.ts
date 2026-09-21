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
    /** Игрок-выброс: не меньше стольких взломов/эдди за 15 минут — иначе «в 10 раз больше медианы» про 1 и 10 взломов ничего не значит. */
    outlierMinBreaches: num(process.env.ANOM_OUTLIER_MIN_BREACHES, 10),
    outlierMinEddies: num(process.env.ANOM_OUTLIER_MIN_EDDIES, 2000),
    /** Во сколько «робастных сигм» (MAD·1.4826) от медианы начинается выброс. */
    outlierSigmas: num(process.env.ANOM_OUTLIER_SIGMAS, 5),
    emissionMin: num(process.env.ANOM_EMISSION_MIN, 1000),
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
  const history = readPulse(db, 60 * MIN, now); // час — база для сравнения «как обычно»
  const samples = history.filter((s) => s.t > now - 15 * MIN);
  const last = history[history.length - 1];
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

  // Скачок эмиссии эдди относительно обычного темпа этой же игры: сумма наград за 3 сэмпла против медианы предыдущих.
  const past = history.slice(0, -3);
  if (past.length >= 20 && recent.length === 3) {
    const base = robustStats(past.map((s) => s.eddies));
    const avgNow = sum(recent, (s) => s.eddies) / 3;
    const limit = base.median + t.outlierSigmas * Math.max(base.sigma, 0.2 * base.median, 1);
    if (avgNow > limit && sum(recent, (s) => s.eddies) >= t.emissionMin) {
      items.push({
        id: "pulse:emission_spike",
        kind: "emission_spike",
        severity: "warn",
        title: "Эмиссия эдди резко выросла",
        detail: `за 3 мин выдано ${sum(recent, (s) => s.eddies)} €$ (${Math.round(avgNow)}/мин), обычно ~${Math.round(base.median)}/мин — щедрый узел, баг или накрутка`,
        at: last.t,
      });
    }
  }

  return items;
}

/** Медиана и «робастная сигма» (MAD·1.4826): выбросы не сдвигают базу, как сдвигали бы среднее и σ. */
export function robustStats(xs: number[]): { median: number; sigma: number } {
  if (xs.length === 0) return { median: 0, sigma: 0 };
  const med = (a: number[]) => {
    const b = [...a].sort((x, y) => x - y);
    const m = b.length >> 1;
    return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2;
  };
  const median = med(xs);
  return { median, sigma: 1.4826 * med(xs.map((x) => Math.abs(x - median))) };
}

const REWARD_REASONS = new Set(["BREACH_EDDIES", "BREACH_LOOT", "SHARD_SCAN"]);

/**
 * Игроки-выбросы за последние 15 минут: взломов или наград заметно больше, чем у остальных активных. Сравнение — с самой игрой
 * (медиана активных), а не с константой: на быстрой игре «много» — другое число, чем на медленной. Нужно не меньше 5 активных.
 */
export function computeOutliers(db: Db, playerName: (key: string) => string, now = Date.now()): AttentionItem[] {
  const t = pulseThresholds();
  const rows = db
    .prepare(
      `SELECT subject_key, field, reason, old_value, new_value, received_at FROM changes
       WHERE received_at > ? AND received_at <= ? AND seq > 0 AND (field = 'counters.breach' OR (field = 'balance' AND reason IN ('BREACH_EDDIES','BREACH_LOOT','SHARD_SCAN')))`,
    )
    .all(now - 15 * MIN, now) as { subject_key: string; field: string; reason: string; old_value: string | null; new_value: string | null; received_at: number }[];

  const breaches = new Map<string, number>();
  const eddies = new Map<string, number>();
  const lastAt = new Map<string, number>();
  for (const r of rows) {
    lastAt.set(r.subject_key, Math.max(lastAt.get(r.subject_key) ?? 0, r.received_at));
    if (r.field === "counters.breach") breaches.set(r.subject_key, (breaches.get(r.subject_key) ?? 0) + 1);
    else if (REWARD_REASONS.has(r.reason)) eddies.set(r.subject_key, (eddies.get(r.subject_key) ?? 0) + Math.max(0, Number(r.new_value ?? 0) - Number(r.old_value ?? 0)));
  }

  const items: AttentionItem[] = [];
  const check = (values: Map<string, number>, min: number, kind: "breaches" | "eddies") => {
    if (values.size < 5) return;
    const { median, sigma } = robustStats([...values.values()]);
    const limit = median + t.outlierSigmas * Math.max(sigma, 1);
    for (const [key, v] of values) {
      if (v < min || v <= limit) continue;
      items.push({
        id: `outlier:${kind}:${key}`,
        kind: "player_outlier",
        severity: "warn",
        title: kind === "breaches" ? "Слишком много взломов" : "Слишком много заработанных эдди",
        detail: `${playerName(key)}: ${kind === "breaches" ? `${v} взломов` : `${v} €$`} за 15 мин, у остальных активных медиана ${Math.round(median)} — накрутка, баг или лучший игрок игры`,
        subjectKey: key,
        at: lastAt.get(key) ?? now,
      });
    }
  };
  check(breaches, t.outlierMinBreaches, "breaches");
  check(eddies, t.outlierMinEddies, "eddies");
  return items;
}

export interface AnomalyEpisode {
  id: string;
  kind: AttentionItem["kind"];
  title: string;
  detail: string;
  firstAt: number;
  lastAt: number;
  /** На скольких шагах перебора условие держалось. */
  steps: number;
}

/**
 * Перебор детекторов по прошлому: «что бы мы показали мастеру, если бы смотрели в момент t» для t от from до to с шагом step.
 * Нужен для подбора порогов по записанным играм и тестовым прогонам: смотрим, где срабатывало, и правим ANOM_*.
 * Только детекторы, которые полностью определяются пульсом и записями до момента t (остальные зависят от текущего состояния).
 */
export function replayAnomalies(db: Db, playerName: (key: string) => string, from: number, to: number, stepMs: number): AnomalyEpisode[] {
  const episodes = new Map<string, AnomalyEpisode>();
  for (let t = from; t <= to; t += stepMs) {
    for (const i of [...computePulseAnomalies(db, t), ...computeOutliers(db, playerName, t)]) {
      const e = episodes.get(i.id);
      if (e) {
        e.lastAt = t;
        e.steps++;
        e.detail = i.detail;
      } else episodes.set(i.id, { id: i.id, kind: i.kind, title: i.title, detail: i.detail, firstAt: t, lastAt: t, steps: 1 });
    }
  }
  return [...episodes.values()].sort((a, b) => a.firstAt - b.firstAt);
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
