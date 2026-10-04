import type { FastifyInstance } from "fastify";
import { createHash } from "node:crypto";
import type { AnnounceResponse, AudioCatalogTrack, AudioChannel, AudioClip, DisplayGroup, DisplayItem } from "../apiTypes.js";
import type { AudioService, AnnounceTargets } from "../audio/audioService.js";
import type { ChannelInput } from "../audio/audioRepository.js";
import { parseWav } from "../audio/wav.js";
import type { Db } from "../db/index.js";
import type { DisplayManager } from "../displays/manager.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { isIntIn, strings } from "../lib/refs.js";

/** Клип громкой связи: IMA ADPCM 16 кГц ≈ 8 КБ/с — 2 МБ хватает на 4 минуты, объявление — секунды. */
export const CLIP_MAX_BYTES = 2 * 1024 * 1024;
/** Имя трека уходит точке как путь в /mb10/tracks: без каталогов и управляющих символов. */
const TRACK_NAME = /^[^/\\\u0000-\u001f]{1,96}$/;
const CLIP_ID = /^[0-9a-f]{64}$/;

type ChannelBody = { name?: unknown; tracks?: unknown; shuffle?: unknown; gapMs?: unknown; volume?: unknown };
type TargetsBody = { all?: unknown; groupIds?: unknown; displayIds?: unknown };

function parseChannel(b: ChannelBody, current?: AudioChannel): { ok: true; value: ChannelInput } | { ok: false; error: string } {
  const name = typeof b.name === "string" ? b.name.trim() : current?.name;
  const tracks = b.tracks === undefined ? current?.tracks : strings(b.tracks);
  const shuffle = b.shuffle ?? current?.shuffle ?? true;
  const gapMs = b.gapMs ?? current?.gapMs ?? 0;
  const volume = b.volume ?? current?.volume ?? 60;
  if (!name || name.length > 64) return { ok: false, error: "name is required (max 64)" };
  if (!tracks || tracks.length > 200 || !tracks.every((t) => TRACK_NAME.test(t))) return { ok: false, error: "tracks: up to 200 file names (no '/')" };
  if (typeof shuffle !== "boolean") return { ok: false, error: "shuffle must be boolean" };
  if (!isIntIn(gapMs, 0, 600_000)) return { ok: false, error: "gapMs must be 0..600000" };
  if (!isIntIn(volume, 0, 100)) return { ok: false, error: "volume must be 0..100" };
  return { ok: true, value: { name, tracks, shuffle, gapMs, volume } };
}

function parseTargets(b: TargetsBody | undefined): AnnounceTargets | null {
  if (!b || typeof b !== "object") return null;
  const groupIds = b.groupIds === undefined ? [] : strings(b.groupIds);
  const displayIds = b.displayIds === undefined ? [] : strings(b.displayIds);
  if (!groupIds || !displayIds) return null;
  if (b.all !== true && groupIds.length === 0 && displayIds.length === 0) return null;
  return { all: b.all === true, groupIds, displayIds };
}

/** Громкость исключения: null — «как у группы/канала». */
function optVolume(v: unknown): number | null | undefined {
  if (v === null) return null;
  return isIntIn(v, 0, 100) ? v : undefined;
}

/**
 * Звук точек (docs/sound-nodes.md): каналы фона, фон групп и исключения точек, каталог треков с карт, клипы и громкая связь.
 * Любая правка того, что должно играть, заканчивается audio.sync() — сервер сам доводит точки до нового состояния.
 */
export function registerAudioRoutes(app: FastifyInstance, db: Db, displays: DisplayManager, audio: AudioService) {
  const repo = audio.repo;

  // ── Каналы ──

  app.get("/api/audio/channels", async (request, reply): Promise<AudioChannel[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    return repo.channels();
  });

  app.post<{ Body: ChannelBody }>("/api/audio/channels", async (request, reply): Promise<AudioChannel | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const c = parseChannel(request.body ?? {});
    if (!c.ok) return reply.code(400).send({ error: c.error });
    if (repo.channelByName(c.value.name)) return reply.code(409).send({ error: "channel with this name already exists" });
    const created = db.transaction(() => {
      const ch = repo.createChannel(c.value);
      logMasterAction(db, master.id, "AUDIO_CHANNEL_CREATE", { channelId: ch.id, name: ch.name, tracks: ch.tracks.length });
      return ch;
    })();
    return created;
  });

  app.put<{ Params: { id: string }; Body: ChannelBody }>("/api/audio/channels/:id", async (request, reply): Promise<AudioChannel | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const current = repo.channel(request.params.id);
    if (!current) return reply.code(404).send({ error: "unknown channel" });
    const c = parseChannel(request.body ?? {}, current);
    if (!c.ok) return reply.code(400).send({ error: c.error });
    const clash = repo.channelByName(c.value.name);
    if (clash && clash.id !== current.id) return reply.code(409).send({ error: "channel with this name already exists" });
    db.transaction(() => {
      repo.updateChannel(current.id, c.value);
      logMasterAction(db, master.id, "AUDIO_CHANNEL_UPDATE", { channelId: current.id, name: c.value.name, tracks: c.value.tracks.length });
    })();
    audio.sync();
    return repo.channel(current.id)!;
  });

  app.delete<{ Params: { id: string } }>("/api/audio/channels/:id", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const current = repo.channel(request.params.id);
    if (!current) return reply.code(404).send({ error: "unknown channel" });
    db.transaction(() => {
      repo.deleteChannel(current.id);
      logMasterAction(db, master.id, "AUDIO_CHANNEL_DELETE", { channelId: current.id, name: current.name });
    })();
    audio.sync();
    return { ok: true };
  });

  app.get("/api/audio/catalog", async (request, reply): Promise<AudioCatalogTrack[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    return audio.catalog();
  });

  // ── Фон групп и точек ──

  app.put<{ Params: { id: string }; Body: { channelId?: unknown; volume?: unknown } }>(
    "/api/display-groups/:id/audio",
    async (request, reply): Promise<DisplayGroup | void> => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const g = displays.repo.getGroup(request.params.id);
      if (!g) return reply.code(404).send({ error: "unknown group" });
      const b = request.body ?? {};
      const channelId = b.channelId ?? null;
      if (channelId !== null && (typeof channelId !== "string" || !repo.channel(channelId))) return reply.code(400).send({ error: "unknown channel" });
      const volume = optVolume(b.volume ?? null);
      if (volume === undefined) return reply.code(400).send({ error: "volume must be 0..100 or null" });
      db.transaction(() => {
        repo.setGroupAudio(g.id, channelId, volume);
        logMasterAction(db, master.id, "AUDIO_GROUP", { groupId: g.id, name: g.name, channel: channelId ? repo.channel(channelId)!.name : null, volume });
      })();
      audio.sync();
      return displays.repo.groupItem(g.id)!;
    },
  );

  /** Исключение точки: channelId null — как у группы, "" — тишина, id — свой канал; volume null — как у группы/канала. */
  app.put<{ Params: { id: string }; Body: { channelId?: unknown; volume?: unknown } }>(
    "/api/displays/:id/audio",
    async (request, reply): Promise<DisplayItem | void> => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const row = displays.repo.get(request.params.id);
      if (!row) return reply.code(404).send({ error: "unknown display" });
      const b = request.body ?? {};
      const channelId = b.channelId ?? null;
      if (channelId !== null && channelId !== "" && (typeof channelId !== "string" || !repo.channel(channelId))) {
        return reply.code(400).send({ error: "unknown channel" });
      }
      const volume = optVolume(b.volume ?? null);
      if (volume === undefined) return reply.code(400).send({ error: "volume must be 0..100 or null" });
      db.transaction(() => {
        repo.setDisplayAudio(row.id, channelId as string | null, volume);
        logMasterAction(db, master.id, "AUDIO_POINT", {
          displayId: row.id,
          channel: channelId === null ? null : channelId === "" ? "" : repo.channel(channelId as string)!.name,
          volume,
        });
      })();
      audio.sync([row.id]);
      return displays.get(row.id)!;
    },
  );

  // ── Клипы ──

  app.get("/api/audio/clips", async (request, reply): Promise<AudioClip[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    return repo.clips();
  });

  /** Клип — WAV (PCM16 или IMA ADPCM, моно) в base64; браузер записывает и кодирует сам. id — sha256 данных. */
  app.post<{ Body: { name?: unknown; data?: unknown; preset?: unknown } }>(
    "/api/audio/clips",
    { bodyLimit: Math.ceil((CLIP_MAX_BYTES * 4) / 3) + 64 * 1024 },
    async (request, reply): Promise<AudioClip | void> => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const b = request.body ?? {};
      const name = typeof b.name === "string" ? b.name.trim() : "";
      if (!name || name.length > 80) return reply.code(400).send({ error: "name is required (max 80)" });
      if (typeof b.data !== "string" || !b.data) return reply.code(400).send({ error: "data must be base64 WAV" });
      const data = Buffer.from(b.data, "base64");
      if (data.length > CLIP_MAX_BYTES) return reply.code(413).send({ error: `clip is larger than ${CLIP_MAX_BYTES} bytes` });
      const wav = parseWav(data);
      if (!wav) return reply.code(400).send({ error: "data must be a mono WAV: PCM 16-bit or IMA ADPCM, 8–48 kHz" });
      const id = createHash("sha256").update(data).digest("hex");
      const clip = db.transaction(() => {
        const saved = repo.saveClip(id, name, data, wav.durationMs, b.preset === true, master.id);
        logMasterAction(db, master.id, "AUDIO_CLIP_SAVE", { clipId: id.slice(0, 12), name, durationMs: wav.durationMs, preset: saved.preset });
        return saved;
      })();
      return clip;
    },
  );

  app.put<{ Params: { id: string }; Body: { preset?: unknown } }>("/api/audio/clips/:id", async (request, reply): Promise<AudioClip | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const clip = CLIP_ID.test(request.params.id) ? repo.clip(request.params.id) : undefined;
    if (!clip) return reply.code(404).send({ error: "unknown clip" });
    if (typeof request.body?.preset !== "boolean") return reply.code(400).send({ error: "preset must be boolean" });
    repo.setClipPreset(clip.id, request.body.preset);
    return repo.clip(clip.id)!;
  });

  /** Прослушать клип в браузере — тот же файл, что уйдёт точкам. */
  app.get<{ Params: { id: string } }>("/api/audio/clips/:id/data", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const data = CLIP_ID.test(request.params.id) ? repo.clipData(request.params.id) : undefined;
    if (!data) return reply.code(404).send({ error: "unknown clip" });
    return reply.type("audio/wav").send(data);
  });

  app.delete<{ Params: { id: string } }>("/api/audio/clips/:id", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const clip = CLIP_ID.test(request.params.id) ? repo.clip(request.params.id) : undefined;
    if (!clip) return reply.code(404).send({ error: "unknown clip" });
    db.transaction(() => {
      repo.deleteClip(clip.id);
      logMasterAction(db, master.id, "AUDIO_CLIP_DELETE", { clipId: clip.id.slice(0, 12), name: clip.name });
    })();
    return { ok: true };
  });

  // ── Громкая связь ──

  /** Ответ сразу; ход по каждой точке — DisplayItem.audio.announce (QUEUED → UPLOADING → PLAYING → DONE). */
  app.post<{ Body: { clipId?: unknown; targets?: TargetsBody; volume?: unknown; chime?: unknown; duck?: unknown } }>(
    "/api/audio/announce",
    async (request, reply): Promise<AnnounceResponse | void> => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const b = request.body ?? {};
      if (typeof b.clipId !== "string" || !CLIP_ID.test(b.clipId)) return reply.code(400).send({ error: "clipId is required" });
      const targets = parseTargets(b.targets);
      if (!targets) return reply.code(400).send({ error: "targets: all, groupIds or displayIds" });
      if (b.volume !== undefined && !isIntIn(b.volume, 0, 100)) return reply.code(400).send({ error: "volume must be 0..100" });
      if (b.duck !== undefined && !isIntIn(b.duck, 0, 100)) return reply.code(400).send({ error: "duck must be 0..100" });
      if (b.chime !== undefined && typeof b.chime !== "boolean") return reply.code(400).send({ error: "chime must be boolean" });
      const clip = repo.clip(b.clipId);
      const r = audio.announce(b.clipId, targets, {
        volume: b.volume as number | undefined,
        chime: b.chime as boolean | undefined,
        duck: b.duck as number | undefined,
      });
      if (!clip || !r) return reply.code(404).send({ error: "unknown clip" });
      logMasterAction(db, master.id, "AUDIO_ANNOUNCE", {
        clip: clip.name,
        points: r.results.filter((x) => x.ok).length,
        skipped: r.results.filter((x) => !x.ok).length,
      });
      return { id: r.id, clipName: clip.name, results: r.results };
    },
  );

  app.post<{ Body: { targets?: TargetsBody } }>("/api/audio/announce/stop", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const targets = parseTargets(request.body?.targets ?? { all: true });
    if (!targets) return reply.code(400).send({ error: "targets: all, groupIds or displayIds" });
    const ids = audio.stopAnnouncement(targets);
    logMasterAction(db, master.id, "AUDIO_ANNOUNCE_STOP", { points: ids.length });
    return { ok: true, displayIds: ids };
  });
}
