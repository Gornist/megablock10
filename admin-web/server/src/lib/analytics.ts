import type { Economy, FactionEvents, FactionRow } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { REASON_LABEL_RU, containerIdOf } from "./humanize.js";
import { parseSafe } from "./json.js";
import type { PlayerBase } from "./playerSummary.js";

/** Причины, где деньги лишь переезжают между игроками (пара TRANSFER_OUT/TRANSFER_IN) — в «источниках эмиссии» их нет, иначе шум. */
const TRANSFER_REASONS = new Set(["TRANSFER_OUT", "TRANSFER_IN", "TRANSFER_CANCELLED"]);

const DELTA_SQL = `(CAST(COALESCE(new_value, '0') AS INTEGER) - CAST(COALESCE(old_value, '0') AS INTEGER))`;

/** Джини по неотрицательным остаткам: 0 — поровну, →1 — всё у одного. */
export function gini(values: number[]): number {
  const xs = values.map((v) => Math.max(0, v)).sort((a, b) => a - b);
  const n = xs.length;
  const sum = xs.reduce((a, b) => a + b, 0);
  if (n === 0 || sum === 0) return 0;
  let weighted = 0;
  xs.forEach((x, i) => (weighted += (i + 1) * x));
  return (2 * weighted) / (n * sum) - (n + 1) / n;
}

function percentile(sortedAsc: number[], p: number): number {
  if (sortedAsc.length === 0) return 0;
  const rank = Math.max(1, Math.ceil(p * sortedAsc.length));
  return sortedAsc[Math.min(sortedAsc.length, rank) - 1];
}

/**
 * Экономика: сколько эдди в обороте, как это менялось, откуда оно берётся и
 * как распределено. Серия — накопленная сумма дельт всех записей balance по
 * часам СЕРВЕРА (received_at): часы телефонов разъезжаются, серверные — одни.
 * Чистая функция от БД → кэшируется по версии БД (dbCache.ts).
 */
export function computeEconomy(db: Db, players: PlayerBase[], buckets = 60, excludeKeys: ReadonlySet<string> = new Set()): Economy {
  // Серия — деньги «в обороте»: остаток заменённых и сброшенных сессий в неё не входит (иначе перевыдача удвоила бы эмиссию).
  const rows = (db
    .prepare(`SELECT received_at AS t, subject_key AS k, ${DELTA_SQL} AS delta FROM changes WHERE field = 'balance' ORDER BY received_at ASC`)
    .all() as { t: number; k: string; delta: number }[]).filter((r) => !excludeKeys.has(r.k));

  const series: Economy["series"] = [];
  if (rows.length > 0) {
    const start = rows[0].t;
    const end = rows[rows.length - 1].t;
    const width = Math.max(60_000, Math.ceil((end - start) / buckets));
    const n = Math.floor((end - start) / width) + 1;
    const perBucket = new Array<number>(n).fill(0);
    for (const r of rows) perBucket[Math.floor((r.t - start) / width)] += r.delta;
    let supply = 0;
    perBucket.forEach((d, i) => {
      supply += d;
      series.push({ t: Math.min(end, start + (i + 1) * width), supply });
    });
  }

  const sources = (
    db
      .prepare(`SELECT reason, SUM(${DELTA_SQL}) AS total FROM changes WHERE field = 'balance' GROUP BY reason`)
      .all() as { reason: string; total: number }[]
  )
    .filter((r) => !TRANSFER_REASONS.has(r.reason) && r.total !== 0)
    .map((r) => ({ reason: r.reason, label: REASON_LABEL_RU[r.reason] ?? r.reason, total: r.total }))
    .sort((a, b) => Math.abs(b.total) - Math.abs(a.total));

  const transferVolume = (
    db.prepare(`SELECT COALESCE(SUM(${DELTA_SQL}), 0) AS v FROM changes WHERE field = 'balance' AND reason = 'TRANSFER_IN'`).get() as { v: number }
  ).v;

  const balances = players.map((p) => p.balance);
  const sorted = [...balances].sort((a, b) => a - b);
  const totalSupply = balances.reduce((a, b) => a + b, 0);

  return {
    totalSupply,
    playersCounted: players.length,
    series,
    sources,
    transferVolume,
    distribution: {
      mean: players.length ? Math.round(totalSupply / players.length) : 0,
      median: percentile(sorted, 0.5),
      p90: percentile(sorted, 0.9),
      gini: Math.round(gini(balances) * 100) / 100,
      negative: balances.filter((b) => b < 0).length,
    },
    top: [...players]
      .sort((a, b) => b.balance - a.balance)
      .slice(0, 10)
      .map((p) => ({ publicKeyB64: p.publicKeyB64, callsign: p.callsign, faction: p.faction, balance: p.balance })),
  };
}

export type { FactionEvents, FactionRow };

const emptyEvents = (): FactionEvents => ({ breachesOwn: 0, breachesForeign: 0, alertsSent: 0, alertsSuppressed: 0, alertsReceived: 0 });

/**
 * События фракций, требующие скана истории: чьи узлы ломают (свои/чужие) и
 * кому уходят сигналы СБ. Фракция игрока — текущая (из сводки), владелец узла
 * — из containers. Зависит только от БД → кэшируется по версии БД.
 */
export function computeFactionEvents(db: Db, players: PlayerBase[]): Map<string, FactionEvents> {
  const factionOf = new Map(players.map((p) => [p.publicKeyB64, p.faction]));
  const owner = new Map(
    (db.prepare(`SELECT id, owner_faction FROM containers`).all() as { id: string; owner_faction: string | null }[]).map((c) => [c.id, c.owner_faction ?? ""]),
  );
  const out = new Map<string, FactionEvents>();
  const of = (faction: string) => {
    let e = out.get(faction);
    if (!e) out.set(faction, (e = emptyEvents()));
    return e;
  };
  for (const p of players) of(p.faction);

  const rows = db
    .prepare(`SELECT subject_key, field, new_value, source_ref FROM changes WHERE field IN ('counters.breach', 'counters.alert')`)
    .all() as { subject_key: string; field: string; new_value: string | null; source_ref: string | null }[];

  for (const r of rows) {
    const playerFaction = factionOf.get(r.subject_key);
    if (playerFaction === undefined) continue;
    const containerId = containerIdOf(r.source_ref);
    const ownerFaction = containerId ? owner.get(containerId) : undefined;

    if (r.field === "counters.breach") {
      if (ownerFaction === undefined || ownerFaction === "") continue; // узел без хозяина/неизвестный — ни «свой», ни «чужой»
      if (ownerFaction === playerFaction) of(playerFaction).breachesOwn += 1;
      else of(playerFaction).breachesForeign += 1;
    } else {
      const suppressed = parseSafe<{ suppressed?: boolean }>(r.new_value)?.suppressed === true;
      if (suppressed) of(playerFaction).alertsSuppressed += 1;
      else {
        of(playerFaction).alertsSent += 1;
        if (ownerFaction) of(ownerFaction).alertsReceived += 1;
      }
    }
  }
  return out;
}

/** Сводка по фракциям: сумма по игрокам + события (events — из computeFactionEvents). online считается на каждый запрос. */
export function buildFactionRows(players: (PlayerBase & { online: boolean })[], events: Map<string, FactionEvents>): FactionRow[] {
  const rows = new Map<string, FactionRow>();
  const rowOf = (faction: string) => {
    let r = rows.get(faction);
    if (!r) {
      r = {
        faction,
        players: 0,
        online: 0,
        totalBalance: 0,
        avgBalance: 0,
        daemons: 0,
        shards: 0,
        breaches: { success: 0, partial: 0, fail: 0 },
        slotsClaimed: 0,
        ...emptyEvents(),
        ...(events.get(faction) ?? {}),
      };
      rows.set(faction, r);
    }
    return r;
  };
  for (const p of players) {
    const r = rowOf(p.faction);
    r.players += 1;
    if (p.online) r.online += 1;
    r.totalBalance += p.balance;
    r.daemons += p.daemonCount;
    r.shards += Object.values(p.shardsByTier).reduce((a, b) => a + b, 0);
    r.breaches.success += p.breaches.success;
    r.breaches.partial += p.breaches.partial;
    r.breaches.fail += p.breaches.fail;
    r.slotsClaimed += p.slotsClaimed;
  }
  // Фракция, у которой есть только «чужие» события (владеет узлом, игроков ещё нет), тоже видна в таблице.
  for (const faction of events.keys()) rowOf(faction);
  for (const r of rows.values()) r.avgBalance = r.players ? Math.round(r.totalBalance / r.players) : 0;
  return [...rows.values()].sort((a, b) => b.totalBalance - a.totalBalance);
}

