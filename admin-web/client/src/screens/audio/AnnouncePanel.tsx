import { useCallback, useRef, useState } from "react";
import { api } from "../../api/client";
import type { AnnounceResponse, AudioClip, DisplayGroup, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, Panel } from "../../design/components";
import { ClipRow, SaveClipDialog, type ClipDraft } from "./AnnounceClips";
import { AnnounceTargets } from "./AnnounceTargets";
import { announceActive } from "./audioUtil";
import { AnnounceProgressList } from "./PointAudio";
import { useAnnounceTargets } from "./useAnnounceTargets";
import { useRecorder } from "./useRecorder";
import { toClipWav } from "./wavEncoder";

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
  const t = useAnnounceTargets(points);
  const [volume, setVolume] = useState(80);
  const [chime, setChime] = useState(true);
  const [draft, setDraft] = useState<ClipDraft | null>(null);
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
  const { targets, targetCount } = t;

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
          <AnnounceTargets t={t} groups={groups} points={points} />
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
          <AnnounceProgressList points={tracked} />
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
