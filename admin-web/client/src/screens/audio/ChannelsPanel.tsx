import { useState } from "react";
import { api } from "../../api/client";
import type { AudioCatalogTrack, AudioChannel, DisplayGroup, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppDialog, AppInput, Panel } from "../../design/components";

/**
 * Каналы — плейлисты фона («Радио «Неон»», «Реклама корпораций», «Дождь и город»). Треки — файлы, заранее записанные на карты
 * точек (/mb10/tracks); по сети гоняется только список имён. Каталог — что точки доложили со своих карт.
 */
export function ChannelsPanel({
  channels,
  catalog,
  groups,
  points,
  onChanged,
}: {
  channels: AudioChannel[];
  catalog: AudioCatalogTrack[];
  groups: DisplayGroup[];
  points: DisplayItem[];
  onChanged: () => void;
}) {
  const [editing, setEditing] = useState<AudioChannel | "new" | null>(null);
  const [removing, setRemoving] = useState<AudioChannel | null>(null);
  const usedBy = (c: AudioChannel) => {
    const g = groups.filter((x) => x.audioChannelId === c.id).length;
    const p = points.filter((x) => x.audio?.overrideChannelId === c.id).length;
    return [g ? `групп: ${g}` : "", p ? `точек отдельно: ${p}` : ""].filter(Boolean).join(", ") || "не назначен";
  };
  return (
    <Panel title={`Каналы (${channels.length})`} action={<AppButton onClick={() => setEditing("new")}>+ канал</AppButton>}>
      {channels.length === 0 ? (
        <p className="hint-text">Каналов нет. Канал — список треков с карт точек; назначьте его группе, и вся локация заиграет.</p>
      ) : (
        <ul className="sound-channels">
          {channels.map((c) => (
            <li key={c.id} className="sound-channel">
              <span className="sound-channel-name">{c.name}</span>
              <span className="hint-text">
                {c.tracks.length} тр. · {c.shuffle ? "вперемешку" : "по порядку"} · {c.volume}%{c.gapMs ? ` · пауза ${c.gapMs / 1000} с` : ""} · {usedBy(c)}
              </span>
              <span className="display-group-actions">
                <AppButton onClick={() => setEditing(c)}>Изменить</AppButton>
                <AppButton variant="danger" onClick={() => setRemoving(c)}>
                  Удалить
                </AppButton>
              </span>
            </li>
          ))}
        </ul>
      )}
      {editing && (
        <ChannelDialog
          channel={editing === "new" ? undefined : editing}
          catalog={catalog}
          audioPoints={points.length}
          onCancel={() => setEditing(null)}
          onDone={() => {
            setEditing(null);
            onChanged();
          }}
        />
      )}
      {removing && (
        <DeleteChannelDialog
          channel={removing}
          onCancel={() => setRemoving(null)}
          onDone={() => {
            setRemoving(null);
            onChanged();
          }}
        />
      )}
    </Panel>
  );
}

function ChannelDialog({
  channel,
  catalog,
  audioPoints,
  onCancel,
  onDone,
}: {
  channel?: AudioChannel;
  catalog: AudioCatalogTrack[];
  audioPoints: number;
  onCancel: () => void;
  onDone: () => void;
}) {
  const [name, setName] = useState(channel?.name ?? "");
  const [tracks, setTracks] = useState<string[]>(channel?.tracks ?? []);
  const [shuffle, setShuffle] = useState(channel?.shuffle ?? true);
  const [volume, setVolume] = useState(channel?.volume ?? 60);
  const [gap, setGap] = useState(String((channel?.gapMs ?? 0) / 1000));
  const [manual, setManual] = useState("");
  const [filter, setFilter] = useState("");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сохранить канал" });

  const add = (t: string) => {
    const name = t.trim();
    if (name && !tracks.includes(name)) setTracks([...tracks, name]);
  };
  const count = new Map(catalog.map((t) => [t.name, t.points]));
  const needle = filter.trim().toLocaleLowerCase("ru");
  const available = catalog.filter((t) => !tracks.includes(t.name) && (!needle || t.name.toLocaleLowerCase("ru").includes(needle)));

  async function save() {
    const body = { name: name.trim(), tracks, shuffle, volume, gapMs: Math.round(Math.max(0, Number(gap) || 0) * 1000) };
    const r = await run(() => (channel ? api.put(`/api/audio/channels/${channel.id}`, body) : api.post("/api/audio/channels", body)));
    if (r.ok) onDone();
  }

  return (
    <AppDialog
      wide
      title={channel ? `Канал «${channel.name}»` : "Новый канал"}
      confirmText={busy ? "Сохраняю…" : "Сохранить"}
      confirmDisabled={busy || !name.trim()}
      onConfirm={save}
      onCancel={onCancel}
    >
      <div className="master-form sound-channel-form">
        <label className="status-caps">Название</label>
        <AppInput autoFocus value={name} maxLength={64} onChange={(e) => setName(e.target.value)} placeholder="Радио «Неон»" />
        <div className="sound-options">
          <label className="sound-check">
            <input type="checkbox" checked={shuffle} onChange={(e) => setShuffle(e.target.checked)} /> вперемешку
          </label>
          <label className="sound-check">
            громкость
            <input type="range" min={0} max={100} value={volume} onChange={(e) => setVolume(Number(e.target.value))} aria-label="громкость канала" />
            <span className="mono">{volume}</span>
          </label>
          <label className="sound-check">
            пауза между треками, с
            <input className="app-input sound-volume" type="number" min={0} max={600} value={gap} onChange={(e) => setGap(e.target.value)} aria-label="пауза" />
          </label>
        </div>
        <label className="status-caps">Треки канала ({tracks.length})</label>
        <ol className="sound-tracklist" aria-label="треки канала">
          {tracks.length === 0 && <li className="hint-text">пусто — канал будет молчать</li>}
          {tracks.map((t, i) => (
            <li key={t}>
              <span className="mono">{t}</span>
              {count.has(t) ? (
                count.get(t)! < audioPoints && (
                  <span className="hint-text">
                    {" "}
                    · есть на {count.get(t)} из {audioPoints}
                  </span>
                )
              ) : (
                <span className="login-error"> · ни одна точка не докладывала этот файл</span>
              )}
              <span className="sound-clip-actions">
                <button type="button" className="icon-button" title="выше" disabled={i === 0} onClick={() => setTracks(move(tracks, i, -1))}>
                  ↑
                </button>
                <button type="button" className="icon-button" title="убрать" onClick={() => setTracks(tracks.filter((x) => x !== t))}>
                  ✕
                </button>
              </span>
            </li>
          ))}
        </ol>
        <label className="status-caps">С карт точек ({catalog.length})</label>
        {catalog.length > 6 && <AppInput value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="поиск по имени файла" />}
        <div className="sound-catalog" aria-label="каталог треков">
          {catalog.length === 0 && <span className="hint-text">точки ещё не доложили содержимое карт — впишите имя файла вручную</span>}
          {available.map((t) => (
            <button key={t.name} type="button" className="sound-catalog-item" onClick={() => add(t.name)} title={`есть на ${t.points} из ${audioPoints}`}>
              + {t.name}
            </button>
          ))}
        </div>
        <div className="display-actions">
          <AppInput
            value={manual}
            onChange={(e) => setManual(e.target.value)}
            className="sound-manual"
            placeholder="имя файла, например ad-arasaka-03.mp3"
            aria-label="трек вручную"
          />
          <AppButton
            onClick={() => {
              add(manual);
              setManual("");
            }}
            disabled={!manual.trim()}
          >
            добавить
          </AppButton>
        </div>
        {error && <div className="login-error">{error}</div>}
      </div>
    </AppDialog>
  );
}

function move<T>(list: T[], i: number, d: number): T[] {
  const next = [...list];
  [next[i], next[i + d]] = [next[i + d], next[i]];
  return next;
}

function DeleteChannelDialog({ channel, onCancel, onDone }: { channel: AudioChannel; onCancel: () => void; onDone: () => void }) {
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось удалить канал" });
  return (
    <AppDialog
      title={`Удалить канал «${channel.name}»?`}
      body="Группы и точки, где он играет, замолчат — назначьте им другой канал."
      confirmText={busy ? "Удаляю…" : "Удалить"}
      confirmVariant="danger"
      confirmDisabled={busy}
      onConfirm={async () => {
        const r = await run(() => api.delete(`/api/audio/channels/${channel.id}`));
        if (r.ok) onDone();
      }}
      onCancel={onCancel}
    >
      {error && <div className="login-error">{error}</div>}
    </AppDialog>
  );
}
