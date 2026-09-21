import type { PulseSample } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { ONLINE_WINDOW_MS, activePlayers, getPlayerBase, withOnline } from "./playerSummary.js";

/**
 * «Пульс игры»: раз в минуту снимок метрик (активность на площадке + здоровье приёма записей), пишется в таблицу pulse_samples.
 * Счётчики приёма копятся в памяти (routes/changes.ts зовёт pulse*), сэмплер их сбрасывает; показатели игры берутся из changes за тот же интервал.
 * Детекторы аномалий (lib/anomalies.ts) читают эти сэмплы, а не сырые запросы — так «нормально» определяется по самой игре.
 */

export const PULSE_INTERVAL_MS = Number(process.env.PULSE_INTERVAL_MS ?? 60_000);
const RETENTION_MS = 7 * 24 * 60 * 60 * 1000;

export type RejectCategory = "signature" | "malformed" | "unknown" | "seq" | "actor" | "provision" | "other";

export function categorizeReject(error: string): RejectCategory {
  if (error === "invalid signature") return "signature";
  if (error === "malformed record") return "malformed";
  if (error.startsWith("unknown ")) return "unknown";
  if (error.startsWith("seq ")) return "seq";
  if (error.startsWith("provision ")) return "provision";
  if (error.startsWith("actor ") || error.startsWith("MASTER_OVERRIDE")) return "actor";
  return "other";
}

interface Counters {
  records: number;
  heartbeats: number;
  rejectedBy: Record<string, number>;
  rateLimited: number;
  secretDenied: number;
  requests: number;
  latencySumMs: number;
  latencyMaxMs: number;
}

const emptyCounters = (): Counters => ({ records: 0, heartbeats: 0, rejectedBy: {}, rateLimited: 0, secretDenied: 0, requests: 0, latencySumMs: 0, latencyMaxMs: 0 });
let counters = emptyCounters();

export const pulse = {
  batch(accepted: number, rejectedErrors: string[]) {
    counters.records += accepted;
    for (const e of rejectedErrors) {
      const c = categorizeReject(e);
      counters.rejectedBy[c] = (counters.rejectedBy[c] ?? 0) + 1;
    }
  },
  heartbeat() {
    counters.heartbeats += 1;
  },
  rateLimited() {
    counters.rateLimited += 1;
  },
  secretDenied() {
    counters.secretDenied += 1;
  },
  request(elapsedMs: number) {
    counters.requests += 1;
    counters.latencySumMs += elapsedMs;
    counters.latencyMaxMs = Math.max(counters.latencyMaxMs, elapsedMs);
  },
};

export function resetPulseCounters() {
  counters = emptyCounters();
}

const REWARD_REASONS = new Set(["BREACH_EDDIES", "BREACH_LOOT", "SHARD_SCAN"]);

/** Снимает сэмпл за интервал (now − intervalMs, now], сбрасывает счётчики приёма и пишет строку в pulse_samples. */
export function takePulseSample(db: Db, now = Date.now(), intervalMs = PULSE_INTERVAL_MS): PulseSample {
  const c = counters;
  counters = emptyCounters();

  const since = now - intervalMs;
  const rows = db
    .prepare(`SELECT field, reason, old_value, new_value FROM changes WHERE received_at > ? AND received_at <= ? AND reason != 'MASTER_OVERRIDE'`)
    .all(since, now) as { field: string; reason: string; old_value: string | null; new_value: string | null }[];
  let breaches = 0,
    eddies = 0,
    transfers = 0;
  for (const r of rows) {
    if (r.field === "counters.breach") breaches++;
    if (r.reason === "TRANSFER_IN") transfers++;
    if (r.field === "balance" && REWARD_REASONS.has(r.reason)) eddies += Math.max(0, Number(r.new_value ?? 0) - Number(r.old_value ?? 0));
  }

  const undelivered = (db.prepare(`SELECT COUNT(*) AS n FROM master_pending WHERE delivered = 0`).get() as { n: number }).n;
  const online = withOnline(activePlayers(getPlayerBase(db)), now).filter((p) => now - p.lastSeenAt < ONLINE_WINDOW_MS).length;

  const rejected = Object.values(c.rejectedBy).reduce((a, b) => a + b, 0);
  const sample: PulseSample = {
    t: now,
    online,
    records: c.records,
    heartbeats: c.heartbeats,
    rejected,
    rejectedBy: c.rejectedBy,
    rateLimited: c.rateLimited,
    secretDenied: c.secretDenied,
    requests: c.requests,
    latencyAvgMs: c.requests ? Math.round(c.latencySumMs / c.requests) : 0,
    latencyMaxMs: Math.round(c.latencyMaxMs),
    breaches,
    eddies,
    transfers,
    undelivered,
  };

  db.prepare(`INSERT OR REPLACE INTO pulse_samples (t, data) VALUES (?, ?)`).run(now, JSON.stringify(sample));
  db.prepare(`DELETE FROM pulse_samples WHERE t < ?`).run(now - RETENTION_MS);
  return sample;
}

/** Сэмплы за последние windowMs, по возрастанию времени. */
export function readPulse(db: Db, windowMs: number, now = Date.now()): PulseSample[] {
  const rows = db.prepare(`SELECT data FROM pulse_samples WHERE t > ? AND t <= ? ORDER BY t ASC`).all(now - windowMs, now) as { data: string }[];
  return rows.map((r) => JSON.parse(r.data) as PulseSample);
}

/** Фоновый сэмплер — только из index.ts (не из buildApp/тестов). Возвращает функцию остановки. */
export function schedulePulse(db: Db, intervalMs = PULSE_INTERVAL_MS): () => void {
  const tick = () => {
    try {
      takePulseSample(db, Date.now(), intervalMs);
    } catch (err) {
      console.error("pulse sample failed:", err);
    }
  };
  const timer = setInterval(tick, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
