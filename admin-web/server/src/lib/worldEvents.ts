import type { Db } from "../db/index.js";
import type { AudioService } from "../audio/audioService.js";
import { recordMasterAlert } from "./worldEventLog.js";

/**
 * Быстрые события «Сети» на точки площадки (docs/netrun-world-records.md, §3): свет, звук, экран точки — там, где важна
 * мгновенность. Данные они не меняют и потеряться могут без вреда: решающее остаётся в записях мира (синк), поэтому здесь нет
 * очереди и догонки — событие живёт `ttl_ms` (≈ 5 с), просроченное и повторное отбрасываются.
 * «Кому» решает коллектор: Мост знает только узел и терминал, а привязку точек держит коллектор (net_point_links).
 */

export const WORLD_EVENT_KINDS = ["run.enter", "run.exit", "trace.level", "ice.hunt", "flatline", "lockdown", "alert.master"] as const;
export type WorldEventKind = (typeof WORLD_EVENT_KINDS)[number];

export interface WorldEvent {
  id: string;
  kind: WorldEventKind;
  ts: number;
  ttlMs: number;
  node: string | null;
  terminal: string | null;
  session: string | null;
  level: string | null;
}

/** Описание вида для экрана настройки: когда возникает и на какие точки идёт (по таблице §3 контракта). */
export const WORLD_EVENT_INFO: Record<WorldEventKind, { label: string; when: string; byTerminal: boolean; byNode: boolean }> = {
  "run.enter": { label: "Вход в Сеть", when: "сессия стала активной (курок нажат)", byTerminal: true, byNode: false },
  "run.exit": { label: "Выход из Сети", when: "сессия закрылась с любым исходом", byTerminal: true, byNode: false },
  "trace.level": { label: "Уровень trace", when: "сменился уровень (SUSPICIOUS → TRACE → LOCKDOWN)", byTerminal: true, byNode: true },
  "ice.hunt": { label: "Охота Black ICE", when: "проснулся Black ICE", byTerminal: false, byNode: true },
  flatline: { label: "Флэтлайн", when: "нетраннера поймал Black ICE", byTerminal: true, byNode: true },
  lockdown: { label: "Локдаун узла", when: "узел закрыт (Soft ICE или правило)", byTerminal: false, byNode: true },
  "alert.master": { label: "Тревога мастеру", when: "новая тревога аудитора — только панель мастера, не площадка", byTerminal: false, byNode: false },
};

const MAX_ID = 100;
const MAX_REF = 100;
const MAX_TTL_MS = 60_000;
const DEFAULT_TTL_MS = 5_000;
const SEEN_KEEP = 2000;

const isKind = (v: unknown): v is WorldEventKind => typeof v === "string" && (WORLD_EVENT_KINDS as readonly string[]).includes(v);
const refOrNull = (v: unknown): string | null | undefined => (v === undefined || v === null ? null : typeof v === "string" && v.length <= MAX_REF ? v : undefined);

/** Разбор одного события из тела запроса; null — не по контракту (неизвестный вид, нет id/ts, длинные поля). */
export function parseWorldEvent(raw: unknown): WorldEvent | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== "string" || r.id.length === 0 || r.id.length > MAX_ID || !isKind(r.kind)) return null;
  if (typeof r.ts !== "number" || !Number.isSafeInteger(r.ts) || r.ts <= 0) return null;
  const ttl = r.ttl_ms === undefined ? DEFAULT_TTL_MS : r.ttl_ms;
  if (typeof ttl !== "number" || !Number.isSafeInteger(ttl) || ttl < 0 || ttl > MAX_TTL_MS) return null;
  const node = refOrNull(r.node);
  const terminal = refOrNull(r.terminal);
  const session = refOrNull(r.session);
  const level = refOrNull(r.level);
  if (node === undefined || terminal === undefined || session === undefined || level === undefined) return null;
  return { id: r.id, kind: r.kind, ts: r.ts, ttlMs: ttl, node, terminal, session, level };
}

export interface WorldEventAction {
  kind: WorldEventKind;
  clipId: string | null;
  volume: number | null;
  chime: boolean;
  enabled: boolean;
}

export interface PointLink {
  displayId: string;
  netNode: string | null;
  terminal: string | null;
}

export interface HandleResult {
  /** Событие принято в работу: по контракту, свежее, не повтор. Это не «что-то сыграло» — настройки может не быть. */
  accepted: number;
  expired: number;
  duplicate: number;
  invalid: number;
  /** Точки, на которые ушло объявление (для проверки мастером и тестов). */
  played: { eventId: string; kind: WorldEventKind; displayIds: string[] }[];
}

interface ActionRow {
  kind: string;
  clip_id: string | null;
  volume: number | null;
  chime: number;
  enabled: number;
}
interface LinkRow {
  display_id: string;
  net_node: string | null;
  terminal: string | null;
}

export function createWorldEvents(db: Db, audio: Pick<AudioService, "announce">) {
  const seen = new Map<string, number>();
  const actionStmt = db.prepare(`SELECT * FROM world_event_actions WHERE kind = ?`);
  const actionsStmt = db.prepare(`SELECT * FROM world_event_actions`);
  const linksStmt = db.prepare(`SELECT * FROM net_point_links`);
  const upsertActionStmt = db.prepare(`
    INSERT INTO world_event_actions (kind, clip_id, volume, chime, enabled) VALUES (@kind, @clip_id, @volume, @chime, @enabled)
    ON CONFLICT(kind) DO UPDATE SET clip_id = @clip_id, volume = @volume, chime = @chime, enabled = @enabled
  `);
  const upsertLinkStmt = db.prepare(`
    INSERT INTO net_point_links (display_id, net_node, terminal) VALUES (@display_id, @net_node, @terminal)
    ON CONFLICT(display_id) DO UPDATE SET net_node = @net_node, terminal = @terminal
  `);
  const deleteLinkStmt = db.prepare(`DELETE FROM net_point_links WHERE display_id = ?`);

  const remember = (id: string, now: number) => {
    seen.set(id, now);
    if (seen.size > SEEN_KEEP) for (const k of [...seen.keys()].slice(0, seen.size - SEEN_KEEP)) seen.delete(k);
  };

  /** Точки, которым адресовано событие: по терминалу и/или по узлу — как в таблице §3 контракта. */
  function targetsOf(e: WorldEvent): string[] {
    const info = WORLD_EVENT_INFO[e.kind];
    const ids = new Set<string>();
    for (const l of linksStmt.all() as LinkRow[]) {
      if (info.byTerminal && e.terminal && l.terminal === e.terminal) ids.add(l.display_id);
      if (info.byNode && e.node && l.net_node === e.node) ids.add(l.display_id);
    }
    return [...ids];
  }

  function run(e: WorldEvent, result: HandleResult): void {
    if (e.kind === "alert.master") {
      recordMasterAlert({ id: e.id, at: e.ts, node: e.node, terminal: e.terminal, session: e.session });
      return;
    }
    const a = actionStmt.get(e.kind) as ActionRow | undefined;
    if (!a || a.enabled !== 1 || !a.clip_id) return;
    const displayIds = targetsOf(e);
    if (displayIds.length === 0) return;
    const r = audio.announce(a.clip_id, { displayIds }, { volume: a.volume ?? undefined, chime: a.chime === 1 });
    if (!r) return; // клип удалили — тихо: событие не повод ронять приём
    const ok = r.results.filter((x) => x.ok).map((x) => x.displayId);
    if (ok.length > 0) result.played.push({ eventId: e.id, kind: e.kind, displayIds: ok });
  }

  return {
    /** Пачка событий от Моста. Невалидное, просроченное и повторное не мешают остальным и не роняют запрос. */
    handle(rawEvents: unknown[], now = Date.now()): HandleResult {
      const result: HandleResult = { accepted: 0, expired: 0, duplicate: 0, invalid: 0, played: [] };
      for (const raw of rawEvents) {
        const e = parseWorldEvent(raw);
        if (!e) {
          result.invalid++;
          continue;
        }
        if (now > e.ts + e.ttlMs) {
          result.expired++;
          continue;
        }
        if (seen.has(e.id)) {
          result.duplicate++;
          continue;
        }
        remember(e.id, now);
        result.accepted++;
        run(e, result);
      }
      return result;
    },

    actions(): WorldEventAction[] {
      return (actionsStmt.all() as ActionRow[]).map((r) => ({
        kind: r.kind as WorldEventKind,
        clipId: r.clip_id,
        volume: r.volume,
        chime: r.chime === 1,
        enabled: r.enabled === 1,
      }));
    },

    setAction(a: WorldEventAction): void {
      upsertActionStmt.run({ kind: a.kind, clip_id: a.clipId, volume: a.volume, chime: a.chime ? 1 : 0, enabled: a.enabled ? 1 : 0 });
    },

    links(): PointLink[] {
      return (linksStmt.all() as LinkRow[]).map((l) => ({ displayId: l.display_id, netNode: l.net_node, terminal: l.terminal }));
    },

    /** Пустые узел и терминал — связи нет (строка удаляется). */
    setLink(l: PointLink): void {
      if (!l.netNode && !l.terminal) deleteLinkStmt.run(l.displayId);
      else upsertLinkStmt.run({ display_id: l.displayId, net_node: l.netNode || null, terminal: l.terminal || null });
    },
  };
}

export type WorldEvents = ReturnType<typeof createWorldEvents>;
