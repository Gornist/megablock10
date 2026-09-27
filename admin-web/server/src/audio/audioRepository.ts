import { randomBytes } from "node:crypto";
import type { AudioChannel, AudioClip } from "../apiTypes.js";
import type { Db } from "../db/index.js";

/** Каналы, клипы и звуковые настройки групп и точек (схема — db/index.ts, миграция 6). */

interface ChannelRow {
  id: string;
  name: string;
  tracks: string;
  shuffle: number;
  gap_ms: number;
  volume: number;
  created_at: number;
}

interface ClipRow {
  id: string;
  name: string;
  bytes: number;
  duration_ms: number;
  preset: number;
  created_at: number;
}

export interface ChannelInput {
  name: string;
  tracks: string[];
  shuffle: boolean;
  gapMs: number;
  volume: number;
}

const toChannel = (r: ChannelRow): AudioChannel => ({
  id: r.id,
  name: r.name,
  tracks: safeList(r.tracks),
  shuffle: r.shuffle === 1,
  gapMs: r.gap_ms,
  volume: r.volume,
});

const toClip = (r: ClipRow): AudioClip => ({
  id: r.id,
  name: r.name,
  bytes: r.bytes,
  durationMs: r.duration_ms,
  preset: r.preset === 1,
  createdAt: r.created_at,
});

export function safeList(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw) as unknown;
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  } catch {
    return [];
  }
}

export class AudioRepository {
  constructor(private readonly db: Db) {}

  // ── Каналы ──

  channels(): AudioChannel[] {
    const rows = this.db.prepare(`SELECT * FROM audio_channels`).all() as ChannelRow[];
    return rows.map(toChannel).sort((a, b) => a.name.localeCompare(b.name, "ru", { sensitivity: "base" }));
  }

  channel(id: string): AudioChannel | undefined {
    const r = this.db.prepare(`SELECT * FROM audio_channels WHERE id = ?`).get(id) as ChannelRow | undefined;
    return r ? toChannel(r) : undefined;
  }

  channelByName(name: string): AudioChannel | undefined {
    const key = name.trim().toLocaleLowerCase("ru");
    return this.channels().find((c) => c.name.toLocaleLowerCase("ru") === key);
  }

  createChannel(c: ChannelInput): AudioChannel {
    const id = `ch-${randomBytes(4).toString("hex")}`;
    this.db
      .prepare(`INSERT INTO audio_channels (id, name, tracks, shuffle, gap_ms, volume, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`)
      .run(id, c.name, JSON.stringify(c.tracks), c.shuffle ? 1 : 0, c.gapMs, c.volume, Date.now());
    return this.channel(id)!;
  }

  updateChannel(id: string, c: ChannelInput): void {
    this.db
      .prepare(`UPDATE audio_channels SET name = ?, tracks = ?, shuffle = ?, gap_ms = ?, volume = ? WHERE id = ?`)
      .run(c.name, JSON.stringify(c.tracks), c.shuffle ? 1 : 0, c.gapMs, c.volume, id);
  }

  /** Канал удалён — группы и точки с ним переходят на тишину (не на «чужой» канал). */
  deleteChannel(id: string): boolean {
    this.db.prepare(`UPDATE display_groups SET audio_channel_id = NULL WHERE audio_channel_id = ?`).run(id);
    this.db.prepare(`UPDATE displays SET audio_channel_id = '' WHERE audio_channel_id = ?`).run(id);
    return this.db.prepare(`DELETE FROM audio_channels WHERE id = ?`).run(id).changes > 0;
  }

  // ── Группы и точки ──

  setGroupAudio(groupId: string, channelId: string | null, volume: number | null): void {
    this.db.prepare(`UPDATE display_groups SET audio_channel_id = ?, audio_volume = ? WHERE id = ?`).run(channelId, volume, groupId);
  }

  setDisplayAudio(displayId: string, channelId: string | null, volume: number | null): void {
    this.db.prepare(`UPDATE displays SET audio_channel_id = ?, audio_volume = ? WHERE id = ?`).run(channelId, volume, displayId);
  }

  setDesired(displayId: string, version: number, state: string): void {
    this.db.prepare(`UPDATE displays SET audio_version = ?, audio_state = ? WHERE id = ?`).run(version, state, displayId);
  }

  setCatalog(displayId: string, names: string[]): void {
    this.db.prepare(`UPDATE displays SET audio_catalog = ? WHERE id = ?`).run(JSON.stringify(names), displayId);
  }

  // ── Клипы ──

  clips(): AudioClip[] {
    const rows = this.db
      .prepare(`SELECT id, name, bytes, duration_ms, preset, created_at FROM audio_clips ORDER BY preset DESC, created_at DESC`)
      .all() as ClipRow[];
    return rows.map(toClip);
  }

  clip(id: string): AudioClip | undefined {
    const r = this.db.prepare(`SELECT id, name, bytes, duration_ms, preset, created_at FROM audio_clips WHERE id = ?`).get(id) as ClipRow | undefined;
    return r ? toClip(r) : undefined;
  }

  clipData(id: string): Buffer | undefined {
    const r = this.db.prepare(`SELECT data FROM audio_clips WHERE id = ?`).get(id) as { data: Buffer } | undefined;
    return r?.data;
  }

  /** Тот же звук (sha256) — та же запись: переименовать / отметить заготовкой. */
  saveClip(id: string, name: string, data: Buffer, durationMs: number, preset: boolean, masterId: string | null): AudioClip {
    this.db
      .prepare(
        `INSERT INTO audio_clips (id, name, data, bytes, duration_ms, preset, created_at, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, preset = MAX(preset, excluded.preset)`,
      )
      .run(id, name, data, data.length, durationMs, preset ? 1 : 0, Date.now(), masterId);
    return this.clip(id)!;
  }

  setClipPreset(id: string, preset: boolean): void {
    this.db.prepare(`UPDATE audio_clips SET preset = ? WHERE id = ?`).run(preset ? 1 : 0, id);
  }

  deleteClip(id: string): boolean {
    return this.db.prepare(`DELETE FROM audio_clips WHERE id = ?`).run(id).changes > 0;
  }
}
