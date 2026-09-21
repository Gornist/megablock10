import type { Db } from "../db/index.js";
import { cachedByDbVersion } from "./dbCache.js";
import { clientVersionsOf, lastPresence } from "./presence.js";
import type { PlayerListItem } from "../apiTypes.js";
import { projectAll } from "./projection.js";

export const ONLINE_WINDOW_MS = 5 * 60 * 1000;

/** Всё, что зависит только от БД (кэшируемо по dbCache.ts) — без online, он зависит от текущего времени, не только от записей. until — «состояние на момент T» (мс, часы сервера). */
export type PlayerBase = Omit<PlayerListItem, "online">;

export function computePlayerBase(db: Db, until?: number): PlayerBase[] {
  return projectAll(db, until)
    .map((s): PlayerBase => ({
      publicKeyB64: s.publicKeyB64,
      callsign: s.callsign,
      faction: s.faction,
      ramCapacity: s.ramCapacity,
      balance: s.balance,
      daemonCount: s.daemons.length,
      shardsByTier: countByTier(s.shards.map((sh) => sh.tier)),
      breaches: sumBreaches(s.counters.breaches),
      slotsClaimed: s.counters.slotsClaimed,
      lastSeenAt: s.lastSeenAt,
    }));
}

/** Время последней активности игрока: запись изменения ИЛИ heartbeat телефона. */
export function seenAt(p: { publicKeyB64: string; lastSeenAt: number }): number {
  return Math.max(p.lastSeenAt, lastPresence(p.publicKeyB64));
}

export function withOnline(base: PlayerBase[], now = Date.now()): PlayerListItem[] {
  return base.map((s): PlayerListItem => {
    const at = seenAt(s);
    const v = clientVersionsOf(s.publicKeyB64);
    return {
      ...s,
      lastSeenAt: at,
      online: now - at < ONLINE_WINDOW_MS,
      ...(v?.appVersion ? { appVersion: v.appVersion } : {}),
      ...(v && Object.keys(v.wireVersions).length > 0 ? { wireVersions: v.wireVersions } : {}),
    };
  });
}

const baseCaches = new WeakMap<Db, () => PlayerBase[]>();

/** Сводка всех игроков, кэшированная по версии БД (см. dbCache.ts) — общая для игроков, фракций, экономики и тревог. */
export function getPlayerBase(db: Db): PlayerBase[] {
  let cached = baseCaches.get(db);
  if (!cached) {
    cached = cachedByDbVersion(db, () => computePlayerBase(db));
    baseCaches.set(db, cached);
  }
  return cached();
}

function countByTier(tiers: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const t of tiers) out[t] = (out[t] ?? 0) + 1;
  return out;
}

function sumBreaches(breaches: Record<string, { success: number; partial: number; fail: number }>) {
  let success = 0,
    partial = 0,
    fail = 0;
  for (const b of Object.values(breaches)) {
    success += b.success;
    partial += b.partial;
    fail += b.fail;
  }
  return { success, partial, fail };
}
