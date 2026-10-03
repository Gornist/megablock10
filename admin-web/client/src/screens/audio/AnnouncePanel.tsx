import { useCallback, useRef, useState } from "react";
import { api, fetchBlob } from "../../api/client";
import type { AnnounceResponse, AudioClip, DisplayGroup, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppDialog, AppInput, Badge, Panel } from "../../design/components";
import { isOnline } from "../displays/displayUtil";
import { announceActive, announcePhaseText, announceTone, formatDuration } from "./audioUtil";
import { useRecorder } from "./useRecorder";
import { toBase64, toClipWav } from "./wavEncoder";

type TargetMode = "all" | "groups" | "points";

/** Готовый к сохранению клип: WAV для точек и адрес для прослушивания в браузере. */
interface Draft {
  wav: Uint8Array;
  durationMs: number;
  url: string;
}

/**
 * Громкая связь: записать объявление (или взять заготовку), выбрать, где его услышат, — и видеть по каждой точке, дошло ли и
 * доиграло ли. Клип уходит точкам кусками с докачкой; фон на время объявления приглушается.
 */
export function AnnouncePanel({
  clips,
  groups,
  points,
  onClipsChanged,
  onAnnounced,
}: {
  clips: AudioClip[];
  groups: DisplayGroup[];
  points: DisplayItem[];
  onClipsChanged: () => void;
  /** Объявление ушло / прервано — перечитать точки, чтобы ход был виден сразу. */
  onAnnounced?: () => void;
}) {
  const [clipId, setClipId] = useState<string | null>(null);
  const [mode, setMode] = useState<TargetMode>("all");
  const [groupIds, setGroupIds] = useState<Set<string>>(new Set());
  const [pointIds, setPointIds] = useState<Set<string>>(new Set());
  const [volume, setVolume] = useState(80);
  const [chime, setChime] = useState(true);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [last, setLast] = useState<AnnounceResponse | null>(null);
  const [prepError, setPrepError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось отправить объявление" });

  const prepare = useCallback(async (data: ArrayBuffer) => {
    setPrepError(null);
    try {
      const { wav, durationMs } = await toClipWav(data);
      setDraft({ wav, durationMs, url: URL.createObjectURL(new Blob([wav as BlobPart], { type: "audio/wav" })) });
    } catch {
      setPrepError("браузер не смог прочитать этот звук — нужен wav, mp3, m4a или ogg");
    }
  }, []);
  const recorder = useRecorder(prepare);

  const selected = clips.find((c) => c.id === clipId) ?? null;
  const groupsWithAudio = groups.filter((g) => points.some((p) => p.groupId === g.id));
  const targets = mode === "all" ? { all: true } : mode === "groups" ? { groupIds: [...groupIds] } : { displayIds: [...pointIds] };
  const targetCount = mode === "all" ? points.length : mode === "groups" ? points.filter((p) => p.groupId && groupIds.has(p.groupId)).length : pointIds.size;

  async function announce() {
    if (!selected) return;
    const res = await run(() => api.post<AnnounceResponse>("/api/audio/announce", { clipId: selected.id, targets, volume, chime }));
    if (res.ok) {
      setLast(res.value);
      onAnnounced?.(); // ход — сразу, не ждать очередного опроса
    }
  }

  async function stopAll() {
    const res = await run(() => api.post("/api/audio/announce/stop", { targets }));
    if (res.ok) onAnnounced?.();
  }

  const toggle = (set: Set<string>, id: string, apply: (s: Set<string>) => void) => {
    const next = new Set(set);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    apply(next);
  };

  // Ход — по последнему объявлению этого экрана, либо по любому, что ещё идёт (запустил другой мастер).
  const tracked = points.filter((p) => p.audio?.announce && (p.audio.announce.id === last?.id || announceActive(p.audio.announce)));
  const anyActive = points.some((p) => announceActive(p.audio?.announce));

  return (
    <Panel title="Громкая связь" className="sound-announce">
      <div className="sound-announce-grid">
        <section>
          <div className="status-caps sound-step">1 · что сказать</div>
          <div className="display-actions">
            {recorder.state === "recording" ? (
              <AppButton variant="danger" onClick={recorder.stop}>
                ■ стоп · {recorder.seconds} с
              </AppButton>
            ) : (
              <AppButton variant="primary" onClick={() => void recorder.start()} disabled={!recorder.available}>
                ● записать
              </AppButton>
            )}
            <AppButton onClick={() => fileRef.current?.click()}>из файла…</AppButton>
            <input
              ref={fileRef}
              type="file"
              accept="audio/*"
              hidden
              data-testid="clip-file"
              onChange={async (e) => {
                const f = e.target.files?.[0];
                e.target.value = "";
                if (f) await prepare(await f.arrayBuffer());
              }}
            />
          </div>
          {!recorder.available && (
            <p className="hint-text">Микрофон браузер даёт только по https или на localhost — запишите на телефон и загрузите «из файла».</p>
          )}
          {(recorder.error || prepError) && <div className="login-error">{recorder.error ?? prepError}</div>}
          <ul className="sound-clips" aria-label="клипы">
            {clips.length === 0 && <li className="hint-text">клипов пока нет — запишите первое объявление</li>}
            {clips.map((c) => (
              <ClipRow key={c.id} clip={c} selected={c.id === clipId} onSelect={() => setClipId(c.id)} onChanged={onClipsChanged} />
            ))}
          </ul>
        </section>

        <section>
          <div className="status-caps sound-step">2 · где</div>
          <div className="sound-target-modes" role="radiogroup" aria-label="кому">
            {(
              [
                ["all", `все точки (${points.length})`],
                ["groups", "группы"],
                ["points", "отдельные точки"],
              ] as const
            ).map(([m, label]) => (
              <label key={m} className="sound-check">
                <input type="radio" name="announce-mode" checked={mode === m} onChange={() => setMode(m)} /> {label}
              </label>
            ))}
          </div>
          {mode === "groups" && (
            <div className="sound-checklist">
              {groupsWithAudio.length === 0 && <span className="hint-text">в группах нет звуковых точек</span>}
              {groupsWithAudio.map((g) => (
                <label key={g.id} className="sound-check">
                  <input type="checkbox" checked={groupIds.has(g.id)} onChange={() => toggle(groupIds, g.id, setGroupIds)} /> {g.name}
                  <span className="hint-text"> · {points.filter((p) => p.groupId === g.id).length}</span>
                </label>
              ))}
            </div>
          )}
          {mode === "points" && (
            <div className="sound-checklist">
              {points.map((p) => (
                <label key={p.id} className="sound-check">
                  <input type="checkbox" checked={pointIds.has(p.id)} onChange={() => toggle(pointIds, p.id, setPointIds)} /> {p.name}
                  {!isOnline(p) && <span className="hint-text"> · нет связи</span>}
                </label>
              ))}
            </div>
          )}
          <div className="sound-options">
            <label className="sound-check">
              громкость
              <input type="range" min={0} max={100} value={volume} onChange={(e) => setVolume(Number(e.target.value))} aria-label="громкость объявления" />
              <span className="mono">{volume}</span>
            </label>
            <label className="sound-check">
              <input type="checkbox" checked={chime} onChange={(e) => setChime(e.target.checked)} /> сигнал перед объявлением
            </label>
          </div>
        </section>

        <section>
          <div className="status-caps sound-step">3 · сказать</div>
          <div className="display-actions">
            <AppButton variant="primary" onClick={() => void announce()} disabled={busy || !selected || targetCount === 0}>
              📢 объявить{selected ? ` «${selected.name}»` : ""} → {targetCount}
            </AppButton>
            {anyActive && (
              <AppButton variant="danger" onClick={() => void stopAll()} disabled={busy}>
                прервать
              </AppButton>
            )}
          </div>
          {!selected && <p className="hint-text">выберите клип слева</p>}
          {error && <div className="login-error">{error}</div>}
          {last && last.results.some((r) => !r.ok) && (
            <p className="hint-text">
              пропущено:{" "}
              {last.results
                .filter((r) => !r.ok)
                .map((r) => `${r.displayId} (${r.error})`)
                .join(", ")}
            </p>
          )}
          {tracked.length > 0 && (
            <ul className="sound-progress" aria-label="ход объявления">
              {tracked.map((p) => {
                const a = p.audio!.announce!;
                return (
                  <li key={p.id}>
                    <span className="sound-progress-name">{p.name}</span>
                    <Badge tone={announceTone(a)}>{announcePhaseText(a)}</Badge>
                    {a.phase === "UPLOADING" && (
                      <span className="sound-bar" aria-hidden>
                        <span style={{ width: `${a.uploadedPct}%` }} />
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      </div>
      {draft && (
        <SaveClipDialog
          draft={draft}
          onCancel={() => {
            URL.revokeObjectURL(draft.url);
            setDraft(null);
          }}
          onSaved={(c) => {
            URL.revokeObjectURL(draft.url);
            setDraft(null);
            setClipId(c.id);
            onClipsChanged();
          }}
        />
      )}
    </Panel>
  );
}

function ClipRow({ clip, selected, onSelect, onChanged }: { clip: AudioClip; selected: boolean; onSelect: () => void; onChanged: () => void }) {
  const { busy, run } = useAsyncAction({ fallbackError: "не удалось" });
  async function play() {
    const blob = await fetchBlob(`/api/audio/clips/${clip.id}/data`);
    const url = URL.createObjectURL(blob);
    const audio = new Audio(url);
    audio.onended = () => URL.revokeObjectURL(url);
    await audio.play();
  }
  return (
    <li className={`sound-clip${selected ? " selected" : ""}`}>
      <label className="sound-check">
        <input type="radio" name="announce-clip" checked={selected} onChange={onSelect} />
        <span className="sound-clip-name">{clip.name}</span>
        <span className="hint-text mono">{formatDuration(clip.durationMs)}</span>
        {clip.preset && <Badge tone="info">заготовка</Badge>}
      </label>
      <span className="sound-clip-actions">
        <button type="button" className="icon-button" title="прослушать" onClick={() => void play()}>
          ▶
        </button>
        <button
          type="button"
          className="icon-button"
          title={clip.preset ? "убрать из заготовок" : "в заготовки"}
          disabled={busy}
          onClick={async () => {
            const r = await run(() => api.put(`/api/audio/clips/${clip.id}`, { preset: !clip.preset }));
            if (r.ok) onChanged();
          }}
        >
          {clip.preset ? "★" : "☆"}
        </button>
        <button
          type="button"
          className="icon-button"
          title="удалить"
          disabled={busy}
          onClick={async () => {
            const r = await run(() => api.delete(`/api/audio/clips/${clip.id}`));
            if (r.ok) onChanged();
          }}
        >
          ✕
        </button>
      </span>
    </li>
  );
}

function SaveClipDialog({ draft, onCancel, onSaved }: { draft: Draft; onCancel: () => void; onSaved: (c: AudioClip) => void }) {
  const [name, setName] = useState("");
  const [preset, setPreset] = useState(false);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сохранить клип" });
  async function save() {
    const r = await run(() => api.post<AudioClip>("/api/audio/clips", { name: name.trim(), data: toBase64(draft.wav), preset }));
    if (r.ok) onSaved(r.value);
  }
  return (
    <AppDialog
      title="Новое объявление"
      body={`${formatDuration(draft.durationMs)} · ${Math.ceil(draft.wav.length / 1024)} КБ — столько уйдёт на каждую точку`}
      confirmText={busy ? "Сохраняю…" : "Сохранить"}
      confirmDisabled={busy || !name.trim()}
      onConfirm={save}
      onCancel={onCancel}
    >
      <div className="master-form">
        <audio controls src={draft.url} className="sound-draft-player" />
        <label className="status-caps">Название</label>
        <AppInput autoFocus value={name} maxLength={80} onChange={(e) => setName(e.target.value)} placeholder="Игра началась" />
        <label className="sound-check">
          <input type="checkbox" checked={preset} onChange={(e) => setPreset(e.target.checked)} /> заготовка — держать вверху списка
        </label>
        {error && <div className="login-error">{error}</div>}
      </div>
    </AppDialog>
  );
}
