import type { AnnounceProgress, AudioCatalogTrack, DisplayAudio } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { DisplayFailure, expectReply, type DisplaySession, type HelloInfo } from "../displays/connection.js";
import type { DisplayManager, OpResult } from "../displays/manager.js";
import {
  CLIP_CHUNK_MAX,
  encodeClipBeginPayload,
  encodeClipChunkPayload,
  encodeJsonPayload,
  encodeListPayload,
  MsgType,
  NackCode,
  type AnnouncePayload,
  type AudioHelloStatus,
  type AudioStatePayload,
} from "../displays/protocol.js";
import { hasRole, type DisplayRow } from "../displays/repository.js";
import { AudioRepository, safeList } from "./audioRepository.js";

/**
 * Звук точек (docs/sound-nodes.md). Сервер хранит, ЧТО должно играть на каждой точке (канал группы или исключение точки,
 * громкость), и доводит до этого каждую точку, как дисплеи — до картинки: версия состояния монотонна, точка докладывает свою в
 * HELLO, отстала — досылаем. Объявление: клип кусками с докачкой (CLIP_BEGIN говорит, сколько уже есть), затем ANNOUNCE;
 * «доиграло» подтверждает HELLO после длительности клипа.
 */

export interface AudioConfig {
  /** Плавность смены фона. */
  fadeMs: number;
  /** Ответ точки на звуковую команду. */
  replyTimeoutMs: number;
  /** Громкость, если не задана ни у точки, ни у группы, ни у канала. */
  defaultVolume: number;
}

const DEFAULTS: AudioConfig = { fadeMs: 1500, replyTimeoutMs: 5000, defaultVolume: 60 };

/** Объявление, если мастер не задал: громкость, сигнал перед ним и до скольких % приглушить фон. */
const ANNOUNCE_DEFAULTS = { volume: 80, chime: true, duck: 15 };
/** «Доиграло?» — опрос точки через столько мс после конца клипа: сразу и ещё раз позже, если точка была занята. */
const ANNOUNCE_DONE_PROBES_MS = [1500, 8000];
/** Страниц LIST за одну операцию — предел на случай точки, у которой total не сходится с выдачей. */
const LIST_MAX_PAGES = 200;

export interface AnnounceTargets {
  all?: boolean;
  groupIds?: string[];
  displayIds?: string[];
}

export interface AnnounceOptions {
  volume?: number;
  chime?: boolean;
  /** До скольких % приглушить фон на время объявления. */
  duck?: number;
}

export class AudioService {
  readonly repo: AudioRepository;
  private readonly cfg: AudioConfig;
  /** Ход последнего объявления на каждой точке — только в памяти, как ход картинки. */
  private readonly progress = new Map<string, AnnounceProgress>();
  /** id объявления = seq ANNOUNCE; от времени запуска, чтобы после перезапуска сервера не повторялись. */
  private nextAnnounceId = Math.floor(Date.now() / 1000) % 0x7fffffff;
  private readonly timers = new Set<NodeJS.Timeout>();

  constructor(
    db: Db,
    private readonly displays: DisplayManager,
    cfg: Partial<AudioConfig> = {},
  ) {
    this.repo = new AudioRepository(db);
    this.cfg = { ...DEFAULTS, ...cfg };
    displays.onHello((row, hello) => this.afterHello(row, hello));
    displays.setAudioView((row) => this.view(row));
  }

  stop(): void {
    for (const t of this.timers) clearTimeout(t);
    this.timers.clear();
  }

  static isAudio(row: Pick<DisplayRow, "roles">): boolean {
    return hasRole(row, "audio");
  }

  private audioRows(): DisplayRow[] {
    return this.displays.repo.list().filter((r) => AudioService.isAudio(r));
  }

  // ── Что должно играть ──

  /** Канал и громкость точки: исключение точки → канал группы → тишина; громкость — точка → группа → канал → по умолчанию. */
  resolve(row: DisplayRow): { channelId: string | null; source: "override" | "group"; volume: number; payload: AudioStatePayload } {
    const group = row.group_id ? this.displays.repo.getGroup(row.group_id) : undefined;
    const source = row.audio_channel_id !== null ? "override" : "group";
    const channelId = (source === "override" ? row.audio_channel_id : (group?.audio_channel_id ?? null)) || null;
    const channel = channelId ? this.repo.channel(channelId) : undefined;
    const volume = row.audio_volume ?? group?.audio_volume ?? channel?.volume ?? this.cfg.defaultVolume;
    const payload: AudioStatePayload = channel
      ? { tracks: channel.tracks, shuffle: channel.shuffle, gapMs: channel.gapMs, volume, fadeMs: this.cfg.fadeMs }
      : { tracks: [], shuffle: false, gapMs: 0, volume, fadeMs: this.cfg.fadeMs };
    return { channelId: channel ? channel.id : null, source, volume, payload };
  }

  /**
   * Пересчитать желаемое для точек (все звуковые, если ids не даны): изменилось — новая версия и отправка. Зовётся после любой
   * правки каналов, групп и исключений, и при первом HELLO звуковой точки.
   */
  sync(ids?: string[]): number {
    let changed = 0;
    for (const row of ids ? ids.map((id) => this.displays.repo.get(id)).filter((r): r is DisplayRow => !!r) : this.audioRows()) {
      if (!AudioService.isAudio(row)) continue;
      const state = JSON.stringify(this.resolve(row).payload);
      if (state === row.audio_state) continue;
      const reported = this.reported(row);
      const version = Math.max(row.audio_version, reported?.v ?? 0) + 1;
      this.repo.setDesired(row.id, version, state);
      changed++;
      if (row.enabled) this.sendState(row.id, true);
    }
    return changed;
  }

  /**
   * Досылка желаемого. changed — желаемое только что поменялось: отправка в работе несёт прежнее (строку она прочитала
   * до правки), поэтому пропускаем только ждущую — та прочитает строку заново. После HELLO (changed=false) — и ту, что в
   * работе: HELLO пришёл в её же сессии, вторая такая же не нужна.
   */
  private sendState(displayId: string, changed = false): void {
    if (this.displays.hasCustom(displayId, "audio-state", changed)) return;
    void this.displays.enqueueCustom(displayId, {
      name: "AUDIO_STATE",
      key: "audio-state",
      run: async (s, row) => {
        if (!row.audio_state) return { outcome: "DISPLAYED" };
        s.send({ type: MsgType.AUDIO_STATE, seq: row.audio_version, payload: Buffer.from(row.audio_state, "utf8") });
        const reply = await s.next(this.cfg.replyTimeoutMs, "OK for AUDIO_STATE");
        if (reply.header.type === MsgType.NACK && reply.payload[0] === NackCode.STALE_VERSION) {
          // Точка впереди сервера (БД из копии): следующая попытка уйдёт с версией выше доложенной.
          const reported = this.reported(row);
          this.repo.setDesired(row.id, Math.max(row.audio_version, reported?.v ?? 0) + 1, row.audio_state);
          throw new DisplayFailure("NACK", "AUDIO_STATE: point has a newer audio version — renumbered", true, NackCode.STALE_VERSION);
        }
        expectReply(reply, MsgType.OK, "AUDIO_STATE");
        this.patchReported(row.id, { v: row.audio_version, vol: JSON.parse(row.audio_state).volume as number });
        return { outcome: "DISPLAYED", version: row.audio_version };
      },
    });
  }

  private reported(row: Pick<DisplayRow, "audio_reported">): AudioHelloStatus | null {
    if (!row.audio_reported) return null;
    try {
      return JSON.parse(row.audio_reported) as AudioHelloStatus;
    } catch {
      return null;
    }
  }

  private patchReported(displayId: string, patch: Partial<AudioHelloStatus>): void {
    const row = this.displays.repo.get(displayId);
    if (!row) return;
    this.displays.repo.setRoles(displayId, undefined, { ...(this.reported(row) ?? { v: 0 }), ...patch });
  }

  private afterHello(row: DisplayRow, hello: HelloInfo): void {
    if (!AudioService.isAudio(row)) return;
    const rep = hello.status.audio;
    if (row.audio_state === null) this.sync([row.id]);
    else if (rep && rep.v < row.audio_version) this.sendState(row.id);
    // Каталог карты: ещё не знаем или число треков изменилось (карту переписали).
    const catalog = row.audio_catalog === null ? null : safeList(row.audio_catalog);
    if (rep?.sd !== false && typeof rep?.tracks === "number" && (catalog === null || catalog.length !== rep.tracks)) this.refreshCatalog(row.id);
    const p = this.progress.get(row.id);
    if (p && rep?.ann && rep.ann.id === p.id && (p.phase === "PLAYING" || p.phase === "UPLOADING")) {
      if (rep.ann.state === "done") p.phase = "DONE";
      else if (rep.ann.state === "stopped") p.phase = "STOPPED";
      else if (rep.ann.state === "failed") {
        p.phase = "FAILED";
        p.error = "точка не смогла сыграть клип";
      }
    }
  }

  private refreshCatalog(displayId: string): void {
    if (this.displays.hasCustom(displayId, "audio-list")) return;
    void this.displays.enqueueCustom(displayId, {
      name: "LIST",
      key: "audio-list",
      quiet: true,
      run: async (s, row) => {
        const names: string[] = [];
        for (let page = 0; page < LIST_MAX_PAGES; page++) {
          const reply = await s.request({ type: MsgType.LIST, payload: encodeListPayload(names.length) }, this.cfg.replyTimeoutMs);
          const body = JSON.parse(reply.payload.toString("utf8")) as { total: number; names: string[] };
          names.push(...body.names.filter((n) => typeof n === "string"));
          if (body.names.length === 0 || names.length >= body.total) break;
        }
        this.repo.setCatalog(row.id, names);
        return { outcome: "DISPLAYED" };
      },
    });
  }

  /** Все треки, доложенные звуковыми точками, — для редактора каналов. */
  catalog(): AudioCatalogTrack[] {
    const counts = new Map<string, number>();
    for (const row of this.audioRows()) for (const name of new Set(safeList(row.audio_catalog))) counts.set(name, (counts.get(name) ?? 0) + 1);
    return [...counts.entries()].map(([name, points]) => ({ name, points })).sort((a, b) => a.name.localeCompare(b.name));
  }

  // ── Громкая связь ──

  resolveTargets(t: AnnounceTargets): { ids: string[]; skipped: { displayId: string; error: string }[] } {
    const rows = this.displays.repo.list();
    const chosen = new Map<string, DisplayRow>();
    for (const r of rows) {
      if (t.all || (r.group_id && t.groupIds?.includes(r.group_id)) || t.displayIds?.includes(r.id)) chosen.set(r.id, r);
    }
    const skipped: { displayId: string; error: string }[] = [];
    for (const id of t.displayIds ?? []) if (!chosen.has(id)) skipped.push({ displayId: id, error: "unknown point" });
    const ids: string[] = [];
    for (const r of chosen.values()) {
      if (!AudioService.isAudio(r)) {
        if (t.displayIds?.includes(r.id)) skipped.push({ displayId: r.id, error: "point has no audio" });
      } else if (!r.enabled) skipped.push({ displayId: r.id, error: "point is disabled" });
      else ids.push(r.id);
    }
    return { ids, skipped };
  }

  announce(
    clipId: string,
    targets: AnnounceTargets,
    opts: AnnounceOptions,
  ): { id: number; results: { displayId: string; ok: boolean; error?: string }[] } | null {
    const clip = this.repo.clip(clipId);
    const data = this.repo.clipData(clipId);
    if (!clip || !data) return null;
    const id = ++this.nextAnnounceId;
    const { ids, skipped } = this.resolveTargets(targets);
    const payload: AnnouncePayload = {
      clip: clip.id,
      volume: clamp(opts.volume ?? ANNOUNCE_DEFAULTS.volume, 0, 100),
      chime: opts.chime ?? ANNOUNCE_DEFAULTS.chime,
      duck: clamp(opts.duck ?? ANNOUNCE_DEFAULTS.duck, 0, 100),
    };
    for (const displayId of ids) {
      const p: AnnounceProgress = {
        id,
        clipId: clip.id,
        clipName: clip.name,
        phase: "QUEUED",
        uploadedPct: 0,
        durationMs: clip.durationMs,
        startedAt: Date.now(),
        playingSince: null,
        error: null,
      };
      this.progress.set(displayId, p);
      void this.displays
        .enqueueCustom(displayId, {
          name: `ANNOUNCE ${id}`,
          key: "announce",
          front: true,
          run: (s) => this.runAnnounce(s, displayId, p, data, payload),
        })
        .then((r: OpResult) => {
          if (this.progress.get(displayId) !== p) return;
          if (r.outcome === "SUPERSEDED") {
            p.phase = "STOPPED";
            p.error = "заменено новым объявлением";
          } else if (r.outcome === "FAILED") {
            p.phase = "FAILED";
            p.error = r.error ?? "не удалось";
          }
        });
    }
    return { id, results: [...ids.map((displayId) => ({ displayId, ok: true })), ...skipped.map((s) => ({ ...s, ok: false }))] };
  }

  private async runAnnounce(s: DisplaySession, displayId: string, p: AnnounceProgress, data: Buffer, payload: AnnouncePayload): Promise<OpResult> {
    const sha = Buffer.from(p.clipId, "hex");
    const timeoutMs = this.cfg.replyTimeoutMs;
    let have = (await s.request({ type: MsgType.CLIP_BEGIN, payload: encodeClipBeginPayload(sha, data.length) }, timeoutMs)).payload.readUInt32BE(0);
    if (have < data.length) {
      p.phase = "UPLOADING";
      p.uploadedPct = Math.floor((have / data.length) * 100);
      while (have < data.length) {
        const chunk = data.subarray(have, Math.min(data.length, have + CLIP_CHUNK_MAX));
        have = (await s.request({ type: MsgType.CLIP_CHUNK, payload: encodeClipChunkPayload(have, chunk) }, timeoutMs)).payload.readUInt32BE(0);
        p.uploadedPct = Math.floor((have / data.length) * 100);
      }
      await s.request({ type: MsgType.CLIP_COMMIT }, timeoutMs);
    }
    p.uploadedPct = 100;
    const ok = await s.request({ type: MsgType.ANNOUNCE, seq: p.id, payload: encodeJsonPayload(payload) }, timeoutMs);
    let durationMs = p.durationMs ?? 0;
    try {
      durationMs = (JSON.parse(ok.payload.toString("utf8")) as { durationMs?: number }).durationMs ?? durationMs;
    } catch {
      // точка не сказала длительность — считаем по клипу
    }
    p.phase = "PLAYING";
    p.durationMs = durationMs;
    p.playingSince = Date.now();
    // «Доиграло» — по HELLO после длительности (и ещё раз позже, если точка была занята).
    for (const delay of ANNOUNCE_DONE_PROBES_MS) {
      const t = setTimeout(() => {
        this.timers.delete(t);
        if (p.phase === "PLAYING") void this.displays.probe(displayId);
      }, durationMs + delay);
      t.unref();
      this.timers.add(t);
    }
    return { outcome: "DISPLAYED" };
  }

  stopAnnouncement(targets: AnnounceTargets): string[] {
    const { ids } = this.resolveTargets(targets);
    for (const displayId of ids) {
      const p = this.progress.get(displayId);
      void this.displays
        .enqueueCustom(displayId, {
          name: "ANNOUNCE_STOP",
          front: true,
          run: async (s) => {
            await s.request({ type: MsgType.ANNOUNCE_STOP }, this.cfg.replyTimeoutMs);
            if (p && (p.phase === "PLAYING" || p.phase === "QUEUED" || p.phase === "UPLOADING")) p.phase = "STOPPED";
            return { outcome: "DISPLAYED" };
          },
        })
        .catch(() => {});
    }
    return ids;
  }

  // ── Для экрана ──

  view(row: DisplayRow): DisplayAudio | null {
    if (!AudioService.isAudio(row)) return null;
    const r = this.resolve(row);
    const reported = this.reported(row);
    const channel = r.channelId ? this.repo.channel(r.channelId) : undefined;
    return {
      channelId: r.channelId,
      channelName: channel?.name ?? null,
      source: r.source,
      volume: r.volume,
      desiredVersion: row.audio_version,
      reportedVersion: reported?.v ?? null,
      applied: row.audio_version > 0 && (reported?.v ?? 0) >= row.audio_version,
      playing: reported?.playing ?? null,
      reportedVolume: reported?.vol ?? null,
      missing: reported?.missing ?? [],
      tracksOnCard: reported?.tracks ?? null,
      sdOk: reported?.sd ?? null,
      overrideChannelId: row.audio_channel_id,
      overrideVolume: row.audio_volume,
      announce: this.progress.get(row.id) ?? null,
    };
  }
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, Math.round(v)));
}
