import { useState } from "react";
import { api, fetchBlob } from "../../api/client";
import type { AudioClip } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppDialog, AppInput, Badge } from "../../design/components";
import { formatDuration } from "./audioUtil";
import { toBase64 } from "./wavEncoder";

/** Готовый к сохранению клип: WAV для точек и адрес для прослушивания в браузере. */
export interface ClipDraft {
  wav: Uint8Array;
  durationMs: number;
  url: string;
}

/** Клип в списке «Громкой связи»: выбрать, прослушать, в заготовки / из заготовок, удалить. */
export function ClipRow({ clip, selected, onSelect, onChanged }: { clip: AudioClip; selected: boolean; onSelect: () => void; onChanged: () => void }) {
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

/** Сохранить записанное или загруженное объявление клипом: название и «заготовка». */
export function SaveClipDialog({ draft, onCancel, onSaved }: { draft: ClipDraft; onCancel: () => void; onSaved: (c: AudioClip) => void }) {
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
