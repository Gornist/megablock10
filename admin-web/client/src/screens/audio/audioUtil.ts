import type { AnnounceProgress, DisplayItem } from "../../api/types";

export const isAudioPoint = (d: DisplayItem) => d.roles.includes("audio") && d.audio !== null;

/** Объявление ещё идёт — ждёт очереди, грузится или играет. */
export const announceActive = (p: AnnounceProgress | null | undefined) => !!p && (p.phase === "QUEUED" || p.phase === "UPLOADING" || p.phase === "PLAYING");

export function announcePhaseText(p: AnnounceProgress): string {
  switch (p.phase) {
    case "QUEUED":
      return "в очереди";
    case "UPLOADING":
      return `загрузка ${p.uploadedPct} %`;
    case "PLAYING":
      return "играет";
    case "DONE":
      return "доиграло";
    case "STOPPED":
      return p.error ? `остановлено: ${p.error}` : "остановлено";
    case "FAILED":
      return `не дошло${p.error ? `: ${p.error}` : ""}`;
  }
}

export function announceTone(p: AnnounceProgress): "ok" | "danger" | "warn" | "accent" | "neutral" {
  if (p.phase === "DONE") return "ok";
  if (p.phase === "FAILED") return "danger";
  if (p.phase === "STOPPED") return "warn";
  if (p.phase === "PLAYING") return "accent";
  return "neutral";
}

export function formatDuration(ms: number): string {
  const s = Math.round(ms / 100) / 10;
  if (s < 60) return `${s.toLocaleString("ru")} с`;
  return `${Math.floor(s / 60)} мин ${Math.round(s % 60)} с`;
}

/** Что точка играет / почему нет — одной строкой для строки точки. */
export function nowPlaying(d: DisplayItem): string {
  const a = d.audio!;
  if (announceActive(a.announce) && a.announce!.phase === "PLAYING") return `📢 ${a.announce!.clipName}`;
  if (!a.channelId) return "тишина";
  if (a.playing) return `♪ ${a.playing}`;
  return `канал «${a.channelName}»`;
}
