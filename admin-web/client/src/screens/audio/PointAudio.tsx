import { useState } from "react";
import { api } from "../../api/client";
import type { AudioChannel, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppSelect, Badge } from "../../design/components";
import { isOnline } from "../displays/displayUtil";
import { announcePhaseText, announceTone, nowPlaying } from "./audioUtil";

/**
 * Звук одной точки — общий для строки точки в «Локациях» и секции «Точка» в карточке узла: что играет, дошло ли, чего нет
 * на карте, и фон точки (канал «как у локации / тишина / свой» и громкость). Сохраняется сразу — сервер доводит точку сам.
 */

/**
 * Звуковой блок точки целиком: что играет, фон точки, ход объявления. `className` — обёртка того места, где он стоит
 * (строка точки на «Локациях» или карточка точки).
 */
export function PointAudioBlock({
  point,
  channels,
  onSaved,
  className,
}: {
  point: DisplayItem;
  channels: AudioChannel[];
  onSaved: () => void;
  className: string;
}) {
  return (
    <div className={className}>
      <PointAudioStatus point={point} />
      <PointAudioControls point={point} channels={channels} onSaved={onSaved} />
      <PointAnnounce point={point} />
    </div>
  );
}

/** Ход объявления по точкам (шаг «3 · сказать»): имя, фаза, полоска загрузки. Пусто — ничего. */
export function AnnounceProgressList({ points }: { points: DisplayItem[] }) {
  if (points.length === 0) return null;
  return (
    <ul className="sound-progress" aria-label="ход объявления">
      {points.map((p) => {
        const a = p.audio!.announce!;
        return (
          <li key={p.id}>
            <span className="sound-progress-name">{p.name}</span>
            <Badge tone={announceTone(a)}>{announcePhaseText(a)}</Badge>
            {a.phase === "UPLOADING" && <UploadBar pct={a.uploadedPct} />}
          </li>
        );
      })}
    </ul>
  );
}

/** Полоска загрузки клипа на точку (ход объявления). */
function UploadBar({ pct }: { pct: number }) {
  return (
    <span className="sound-bar" aria-hidden>
      <span style={{ width: `${pct}%` }} />
    </span>
  );
}

/** Что играет и в каком состоянии: «применено / доходит», нет карты, недостающие треки, громкость. */
function PointAudioStatus({ point }: { point: DisplayItem }) {
  const a = point.audio!;
  const online = isOnline(point);
  return (
    <>
      <span className="sound-point-now">{online ? nowPlaying(point) : "—"}</span>
      <span className="sound-point-flags">
        {!online ? <Badge tone="neutral">нет связи</Badge> : a.applied ? <Badge tone="ok">применено</Badge> : <Badge tone="warn">доходит…</Badge>}
        {a.sdOk === false && <Badge tone="danger">нет карты</Badge>}
        {a.missing.length > 0 && (
          <span title={a.missing.join("\n")}>
            <Badge tone="danger">нет на карте: {a.missing.length}</Badge>
          </span>
        )}
        <span className="hint-text mono">{a.reportedVolume ?? a.volume}%</span>
      </span>
    </>
  );
}

/** Фон точки: исключение поверх локации. «как у локации» — null, «тишина» — "", иначе id канала. */
function PointAudioControls({ point, channels, onSaved }: { point: DisplayItem; channels: AudioChannel[]; onSaved: () => void }) {
  const a = point.audio!;
  const { error, run } = useAsyncAction({ fallbackError: "не удалось сохранить" });
  const save = (channelId: string | null, volume: number | null) =>
    run(() => api.put(`/api/displays/${encodeURIComponent(point.id)}/audio`, { channelId, volume })).then((r) => r.ok && onSaved());
  const value = a.overrideChannelId === null ? "group" : a.overrideChannelId;
  return (
    <span className="sound-controls">
      <AppSelect
        aria-label={`фон точки ${point.id}`}
        value={value}
        onChange={(e) => void save(e.target.value === "group" ? null : e.target.value, a.overrideVolume)}
      >
        <option value="group">как у локации</option>
        <option value="">тишина</option>
        {channels.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </AppSelect>
      <VolumeInput
        key={`p-${a.overrideVolume}`}
        label={`громкость точки ${point.id}`}
        value={a.overrideVolume}
        placeholder="авто"
        onCommit={(v) => void save(a.overrideChannelId, v)}
      />
      {error && <span className="login-error">{error}</span>}
    </span>
  );
}

/** Последнее объявление на точке: «загрузка 40 %», «играет», «доиграло»… Нет объявлений — ничего. */
function PointAnnounce({ point }: { point: DisplayItem }) {
  const p = point.audio?.announce;
  if (!p) return null;
  return (
    <span className="sound-point-flags">
      <span className="hint-text">📢 {p.clipName}</span>
      <Badge tone={announceTone(p)}>{announcePhaseText(p)}</Badge>
      {p.phase === "UPLOADING" && <UploadBar pct={p.uploadedPct} />}
    </span>
  );
}

/** Громкость 0–100 или пусто («как выше»); сохраняется по Enter и при уходе с поля. Пришло новое значение с сервера — key={value} у вызывающего. */
export function VolumeInput({
  label,
  value,
  placeholder,
  onCommit,
}: {
  label: string;
  value: number | null;
  placeholder: string;
  onCommit: (v: number | null) => void;
}) {
  const [text, setText] = useState(value === null ? "" : String(value));
  const commit = () => {
    const t = text.trim();
    const v = t === "" ? null : Math.max(0, Math.min(100, Math.round(Number(t))));
    if (v !== null && Number.isNaN(v)) return setText(value === null ? "" : String(value));
    if (v !== value) onCommit(v);
  };
  return (
    <input
      className="app-input sound-volume"
      type="number"
      min={0}
      max={100}
      aria-label={label}
      title={label}
      placeholder={placeholder}
      value={text}
      onChange={(e) => setText(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => e.key === "Enter" && (e.target as HTMLInputElement).blur()}
    />
  );
}
