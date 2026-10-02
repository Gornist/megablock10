import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import type { NetPointLinkItem, WorldEventActionItem, WorldEventKindInfo, WorldEventsConfig, WorldEventsTestResult } from "../apiTypes.js";
import type { AudioService } from "../audio/audioService.js";
import type { Db } from "../db/index.js";
import type { DisplayManager } from "../displays/manager.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { checkGameSecret } from "../lib/gameSecret.js";
import { RateLimiter } from "../lib/rateLimit.js";
import { createWorldEvents, WORLD_EVENT_INFO, WORLD_EVENT_KINDS, type WorldEventKind } from "../lib/worldEvents.js";

const CLIP_ID = /^[0-9a-f]{64}$/;
/** Событий в одном запросе: Мост шлёт единицы, пачка в сотни — это уже не он. */
const MAX_EVENTS = 50;
const REF = /^[A-Za-z0-9_.:-]{1,100}$/;

const isKind = (v: unknown): v is WorldEventKind => typeof v === "string" && (WORLD_EVENT_KINDS as readonly string[]).includes(v);
const isIntIn = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;

/**
 * Быстрые события «Сети» на точки площадки. `POST /api/world-events` — от Моста: `X-Game-Secret`, без сессии мастера (Мост — машина),
 * без очереди: просроченное (`ttl_ms`) и повторное (`id`) отбрасывается. Настройка «событие → клип» и «точка ↔ узел/терминал» —
 * под сессией мастера. По умолчанию событие ничего не делает: пока мастер не назначил клип, звучать нечему.
 */
export function registerWorldEventsRoutes(app: FastifyInstance, db: Db, displays: DisplayManager, audio: AudioService) {
  const worldEvents = createWorldEvents(db, audio);
  const audioRepo = audio.repo;

  const perMinute = Number(process.env.WORLD_EVENTS_RATE_PER_MIN ?? 600);
  const limiter = perMinute > 0 ? new RateLimiter(perMinute, 60_000) : null;

  app.post<{ Body: { events?: unknown } }>("/api/world-events", async (request, reply) => {
    if (limiter?.hit(request.ip)) {
      reply.header("retry-after", "5");
      return reply.code(429).send({ error: "too many requests" });
    }
    if (!checkGameSecret(request, reply)) return;
    const events = request.body?.events;
    if (!Array.isArray(events)) return reply.code(400).send({ error: "events must be an array" });
    if (events.length > MAX_EVENTS) return reply.code(400).send({ error: `too many events, max ${MAX_EVENTS}` });
    const r = worldEvents.handle(events);
    // accepted — по контракту; остальное — для диагностики Моста (неизвестные поля он игнорирует).
    return { accepted: r.accepted, expired: r.expired, duplicate: r.duplicate, invalid: r.invalid };
  });

  const kinds = (): WorldEventKindInfo[] => WORLD_EVENT_KINDS.map((kind) => ({ kind, ...WORLD_EVENT_INFO[kind] }));

  const config = (): WorldEventsConfig => {
    const byKind = new Map(worldEvents.actions().map((a) => [a.kind, a]));
    const actions: WorldEventActionItem[] = WORLD_EVENT_KINDS.map((kind) => {
      const a = byKind.get(kind);
      return {
        kind,
        clipId: a?.clipId ?? null,
        clipName: a?.clipId ? (audioRepo.clip(a.clipId)?.name ?? null) : null,
        volume: a?.volume ?? null,
        chime: a?.chime ?? true,
        enabled: a?.enabled ?? false,
      };
    });
    const links: NetPointLinkItem[] = worldEvents.links().map((l) => ({
      displayId: l.displayId,
      displayName: displays.repo.get(l.displayId)?.name ?? l.displayId,
      netNode: l.netNode,
      terminal: l.terminal,
    }));
    return { kinds: kinds(), actions, links };
  };

  app.get("/api/net/world-events/config", async (request, reply): Promise<WorldEventsConfig | void> => {
    if (!requireMaster(db, request, reply)) return;
    return config();
  });

  app.put<{ Params: { kind: string }; Body: { clipId?: unknown; volume?: unknown; chime?: unknown; enabled?: unknown } }>(
    "/api/net/world-events/actions/:kind",
    async (request, reply): Promise<WorldEventActionItem | void> => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const kind = request.params.kind;
      if (!isKind(kind)) return reply.code(404).send({ error: "unknown event kind" });
      if (kind === "alert.master") return reply.code(400).send({ error: "alert.master goes only to the master panel" });
      const b = request.body ?? {};
      const clipId = b.clipId === null || b.clipId === undefined || b.clipId === "" ? null : b.clipId;
      if (clipId !== null && (typeof clipId !== "string" || !CLIP_ID.test(clipId) || !audioRepo.clip(clipId))) return reply.code(400).send({ error: "unknown clip" });
      if (b.volume !== undefined && b.volume !== null && !isIntIn(b.volume, 0, 100)) return reply.code(400).send({ error: "volume must be 0..100" });
      if (b.chime !== undefined && typeof b.chime !== "boolean") return reply.code(400).send({ error: "chime must be boolean" });
      if (b.enabled !== undefined && typeof b.enabled !== "boolean") return reply.code(400).send({ error: "enabled must be boolean" });
      worldEvents.setAction({
        kind,
        clipId: clipId as string | null,
        volume: (b.volume as number | null | undefined) ?? null,
        chime: (b.chime as boolean | undefined) ?? true,
        enabled: (b.enabled as boolean | undefined) ?? clipId !== null,
      });
      logMasterAction(db, master.id, "NET_EVENT_ACTION", { kind, clipId: clipId ? (clipId as string).slice(0, 12) : null });
      return config().actions.find((a) => a.kind === kind)!;
    },
  );

  app.put<{ Params: { id: string }; Body: { netNode?: unknown; terminal?: unknown } }>(
    "/api/net/point-links/:id",
    async (request, reply): Promise<{ ok: true } | void> => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const id = request.params.id;
      if (!displays.repo.get(id)) return reply.code(404).send({ error: "unknown point" });
      const ref = (v: unknown): string | null | undefined => (v === undefined || v === null || v === "" ? null : typeof v === "string" && REF.test(v) ? v : undefined);
      const netNode = ref(request.body?.netNode);
      const terminal = ref(request.body?.terminal);
      if (netNode === undefined || terminal === undefined) return reply.code(400).send({ error: "netNode/terminal: letters, digits, '_', '-', '.', ':' (max 100)" });
      worldEvents.setLink({ displayId: id, netNode, terminal });
      logMasterAction(db, master.id, "NET_POINT_LINK", { displayId: id, netNode, terminal });
      return { ok: true };
    },
  );

  /** «Проверить»: то же событие, что пришло бы от Моста, — мастер слышит результат настройки, не дожидаясь забега. */
  app.post<{ Body: { kind?: unknown; node?: unknown; terminal?: unknown } }>("/api/net/world-events/test", async (request, reply): Promise<WorldEventsTestResult | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const b = request.body ?? {};
    if (!isKind(b.kind)) return reply.code(400).send({ error: "unknown event kind" });
    const ref = (v: unknown) => (typeof v === "string" && REF.test(v) ? v : null);
    const r = worldEvents.handle([{ id: `test-${randomUUID()}`, kind: b.kind, ts: Date.now(), ttl_ms: 5000, node: ref(b.node), terminal: ref(b.terminal), session: null, level: null }]);
    logMasterAction(db, master.id, "NET_EVENT_TEST", { kind: b.kind, node: ref(b.node), terminal: ref(b.terminal) });
    return { accepted: r.accepted, playedOn: r.played.flatMap((p) => p.displayIds) };
  });
}
