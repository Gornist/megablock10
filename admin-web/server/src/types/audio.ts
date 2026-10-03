import type { DisplayItem } from "./displays.js";

// ── Звук (docs/sound-nodes.md) ──

/** Канал — плейлист треков с карты точки (имена файлов в /mb10/tracks). */
export interface AudioChannel {
  id: string;
  name: string;
  tracks: string[];
  shuffle: boolean;
  gapMs: number;
  volume: number;
}

/** Трек, доложенный точками (LIST): на скольких точках он есть. */
export interface AudioCatalogTrack {
  name: string;
  points: number;
}

/** Клип громкой связи (объявление или заготовка). */
export interface AudioClip {
  id: string;
  name: string;
  bytes: number;
  durationMs: number;
  preset: boolean;
  createdAt: number;
}

/**
 * Ход объявления на точке: QUEUED — ждёт очереди; UPLOADING — клип докачивается (uploadedPct); PLAYING — играет (с durationMs);
 * DONE — доиграло (подтверждено HELLO); STOPPED — прервано; FAILED — не дошло (error).
 */
export type AnnouncePhase = "QUEUED" | "UPLOADING" | "PLAYING" | "DONE" | "STOPPED" | "FAILED";

export interface AnnounceProgress {
  id: number;
  clipId: string;
  clipName: string;
  phase: AnnouncePhase;
  uploadedPct: number;
  durationMs: number | null;
  startedAt: number;
  playingSince: number | null;
  error: string | null;
}

export interface DisplayAudio {
  /** Что должно играть: канал (null — тишина), откуда (исключение точки / группа), громкость. */
  channelId: string | null;
  channelName: string | null;
  source: "override" | "group";
  volume: number;
  desiredVersion: number;
  /** Что точка доложила последним HELLO. */
  reportedVersion: number | null;
  applied: boolean;
  playing: string | null;
  reportedVolume: number | null;
  /** Треки канала, которых нет на карте точки. */
  missing: string[];
  tracksOnCard: number | null;
  sdOk: boolean | null;
  /** Исключения точки (null — как у группы; channel "" — тишина). */
  overrideChannelId: string | null;
  overrideVolume: number | null;
  announce: AnnounceProgress | null;
}

export interface AnnounceResponse {
  id: number;
  clipName: string;
  results: { displayId: string; ok: boolean; error?: string }[];
}

/** Ответ создания дисплея и смены секрета: секрет показывается только здесь, дальше его не отдаёт ни один запрос. */
export interface DisplaySecretResponse {
  display: DisplayItem;
  secret: string;
  /** Что прошить в дисплей (docs/displays.md, «Первичная настройка»): Wi-Fi вписывается руками, серверу он неизвестен. */
  provisioning: { id: string; secret: string; port: number; width: number; height: number };
}

/** Что уйдёт на дисплей: строка QR (та же, что для печати) и кадр как PNG. */
export interface DisplayPreview {
  qr: string;
  label: string;
  png: string;
  width: number;
  height: number;
  qrVersion: number;
  modules: number;
  /** Пикселей на модуль: 1–2 — телефон может не прочесть с обычного расстояния. */
  scale: number;
}

export type DisplayPushOutcome = "QUEUED" | "DISPLAYED" | "FAILED" | "SUPERSEDED";

export interface DisplayPushResult {
  displayId: string;
  ok: boolean;
  version?: number;
  outcome?: DisplayPushOutcome;
  error?: string;
}

export interface DisplayPushResponse {
  label: string;
  results: DisplayPushResult[];
}
