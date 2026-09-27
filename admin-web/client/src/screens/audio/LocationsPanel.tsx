import { useState } from "react";
import { api } from "../../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppSelect, Badge, Panel } from "../../design/components";
import { useCollapsedGroups } from "../displays/useCollapsedGroups";
import { isOnline, nowPlaying } from "./audioUtil";

/**
 * Что играет где: фон задаётся группе (локации) — каналом и громкостью, у отдельной точки — исключение (свой канал или
 * тишина). Сохраняется сразу; точка на связи переключается за секунды, без связи — догонит при следующем HELLO.
 */
export function LocationsPanel({
  groups,
  points,
  channels,
  onChanged,
}: {
  groups: DisplayGroup[];
  points: DisplayItem[];
  channels: AudioChannel[];
  onChanged: () => void;
}) {
  const [collapsed, toggle] = useCollapsedGroups("mb10_sound_collapsed");
  const known = new Set(groups.map((g) => g.id));
  const ungrouped = points.filter((p) => !p.groupId || !known.has(p.groupId));
  const { error, run } = useAsyncAction({ fallbackError: "не удалось сохранить" });

  const saveGroup = (g: DisplayGroup, channelId: string | null, volume: number | null) =>
    run(() => api.put(`/api/display-groups/${encodeURIComponent(g.id)}/audio`, { channelId, volume })).then((r) => r.ok && onChanged());
  const savePoint = (p: DisplayItem, channelId: string | null, volume: number | null) =>
    run(() => api.put(`/api/displays/${encodeURIComponent(p.id)}/audio`, { channelId, volume })).then((r) => r.ok && onChanged());

  const rows = (list: DisplayItem[]) => (
    <ul className="sound-points">
      {list.map((p) => (
        <PointRow key={p.id} point={p} channels={channels} onSave={(c, v) => void savePoint(p, c, v)} />
      ))}
    </ul>
  );

  return (
    <Panel title="Локации: фон">
      {error && <div className="login-error">{error}</div>}
      <div className="display-groups">
        {groups.map((g) => {
          const members = points.filter((p) => p.groupId === g.id);
          const isCollapsed = collapsed.has(g.id);
          return (
            <section key={g.id} className={`display-group${isCollapsed ? " collapsed" : ""}`} data-group={g.id}>
              <header className="display-group-head">
                <button type="button" className="display-group-toggle" aria-expanded={!isCollapsed} onClick={() => toggle(g.id)}>
                  <span className="display-group-caret">{isCollapsed ? "▸" : "▾"}</span>
                  <span className="display-group-title">{g.name}</span>
                  <span className="hint-text">
                    {members.length} зв. · на связи {members.filter(isOnline).length}/{members.length}
                  </span>
                </button>
                <span className="sound-controls">
                  <AppSelect
                    aria-label={`канал группы ${g.name}`}
                    value={g.audioChannelId ?? ""}
                    onChange={(e) => void saveGroup(g, e.target.value || null, g.audioVolume)}
                  >
                    <option value="">— тишина —</option>
                    {channels.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </AppSelect>
                  <VolumeInput
                    key={`g-${g.audioVolume}`}
                    label={`громкость группы ${g.name}`}
                    value={g.audioVolume}
                    placeholder="авто"
                    onCommit={(v) => void saveGroup(g, g.audioChannelId, v)}
                  />
                </span>
              </header>
              {!isCollapsed && (members.length > 0 ? rows(members) : <p className="hint-text display-group-empty">в группе нет звуковых точек</p>)}
            </section>
          );
        })}
        {ungrouped.length > 0 && (
          <section className={`display-group${collapsed.has("") ? " collapsed" : ""}`}>
            <header className="display-group-head">
              <button type="button" className="display-group-toggle" aria-expanded={!collapsed.has("")} onClick={() => toggle("")}>
                <span className="display-group-caret">{collapsed.has("") ? "▸" : "▾"}</span>
                <span className="display-group-title">Без группы</span>
                <span className="hint-text">{ungrouped.length} зв. — фон только исключением точки</span>
              </button>
            </header>
            {!collapsed.has("") && rows(ungrouped)}
          </section>
        )}
      </div>
    </Panel>
  );
}

function PointRow({
  point,
  channels,
  onSave,
}: {
  point: DisplayItem;
  channels: AudioChannel[];
  onSave: (channelId: string | null, volume: number | null) => void;
}) {
  const a = point.audio!;
  const online = isOnline(point);
  // "override:" — как у группы; "" — тишина; иначе id канала.
  const value = a.overrideChannelId === null ? "group" : a.overrideChannelId;
  return (
    <li className="sound-point" data-point={point.id}>
      <span className="sound-point-name">
        {point.name} <span className="hint-text mono">{point.id}</span>
      </span>
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
      <span className="sound-controls">
        <AppSelect
          aria-label={`фон точки ${point.id}`}
          value={value}
          onChange={(e) => onSave(e.target.value === "group" ? null : e.target.value, a.overrideVolume)}
        >
          <option value="group">как у группы</option>
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
          onCommit={(v) => onSave(a.overrideChannelId, v)}
        />
      </span>
    </li>
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
