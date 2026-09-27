import { api } from "../../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppSelect, Panel } from "../../design/components";
import { useCollapsedGroups } from "../displays/useCollapsedGroups";
import { isOnline } from "./audioUtil";
import { PointAudioControls, PointAudioStatus, VolumeInput } from "./PointAudio";

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

  const rows = (list: DisplayItem[]) => (
    <ul className="sound-points">
      {list.map((p) => (
        <PointRow key={p.id} point={p} channels={channels} onSaved={onChanged} />
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

function PointRow({ point, channels, onSaved }: { point: DisplayItem; channels: AudioChannel[]; onSaved: () => void }) {
  return (
    <li className="sound-point" data-point={point.id}>
      <span className="sound-point-name">
        {point.name} <span className="hint-text mono">{point.id}</span>
      </span>
      <PointAudioStatus point={point} />
      <PointAudioControls point={point} channels={channels} onSaved={onSaved} />
    </li>
  );
}
