import { useEffect, useState } from "react";
import { api, ApiError } from "../../api/client";
import type { DisplayItem, DisplayPreview, DisplayPushResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppDialog, Badge, EmptyState } from "../../design/components";
import { DisplayMock, PushSteps } from "./DisplayMock";
import { StatusBadge } from "./DeviceStatus";
import { PUSH_TONE, pushProgress, scaleWarning, type DisplaySource } from "./displayUtil";

// Этапы «отправлено → загружено» на месте длятся секунды — опрос чаще, чтобы их было видно.
const POLL_PUSH_MS = 1000;

/**
 * «Отправить на дисплей»: выбрать один или несколько дисплеев → макет дисплея с кадром (ровно то, что уйдёт на e-paper) → отправить →
 * по каждому дисплею шкала «подключение → отправлено → загружено → отображено», а макет показывает, что сейчас на экране выбранного
 * дисплея. Картинку рисует сервер, браузер к дисплеям не ходит.
 */
export function DisplayPushDialog({
  source,
  title,
  onClose,
  preselect,
}: {
  source: DisplaySource;
  title: string;
  onClose: () => void;
  /** Сразу отмеченные точки — например, точка этого узла (карточка узла). */
  preselect?: string[];
}) {
  const { data: displays, error: listError } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_PUSH_MS });
  const [selected, setSelected] = useState<string[]>(preselect ?? []);
  const [preview, setPreview] = useState<DisplayPreview | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [sent, setSent] = useState<DisplayPushResponse | null>(null);
  // Чей ход показывает макет после отправки (по умолчанию — первого дисплея).
  const [focus, setFocus] = useState<string | null>(null);
  const send = useAsyncAction({ fallbackError: "не удалось отправить" });

  const usable = (displays ?? []).filter((d) => d.enabled);
  const sizeOf = selected[0] ?? usable[0]?.id;

  // Один дисплей — выбрать его сразу.
  useEffect(() => {
    if (displays && selected.length === 0 && usable.length === 1) setSelected([usable[0].id]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [displays]);

  // Предпросмотр под размер первого выбранного дисплея (у всех CrowPanel он один и тот же).
  const sourceKey = JSON.stringify(source);
  useEffect(() => {
    let cancelled = false;
    setPreviewError(null);
    api
      .post<DisplayPreview>("/api/displays/preview", {
        source,
        displayId: sizeOf,
      })
      .then((p) => !cancelled && setPreview(p))
      .catch((err) => !cancelled && setPreviewError(err instanceof ApiError ? err.message : "не удалось построить предпросмотр"));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourceKey, sizeOf]);

  function toggle(id: string) {
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  }

  async function submit() {
    const res = await send.run(() =>
      api.post<DisplayPushResponse>("/api/displays/push", {
        displayIds: selected,
        source,
      }),
    );
    if (res.ok) setSent(res.value);
  }

  const warning = preview ? scaleWarning(preview.scale) : null;
  const mockId = sent ? (focus ?? sent.results[0]?.displayId ?? null) : null;
  const mockDisplay = mockId ? displays?.find((d) => d.id === mockId) : undefined;
  const mockResult = sent?.results.find((r) => r.displayId === mockId);
  const mockProgress = mockResult ? pushProgress(mockResult, mockDisplay) : null;
  // Под макетом — только то, чего не видно по отметке: причина ошибки или повтора, показанная версия.
  const mockNote =
    mockProgress?.state === "failed" || mockProgress?.push?.phase === "RETRY"
      ? mockProgress.text
      : mockProgress?.state === "shown"
        ? `v${mockDisplay?.displayedVersion ?? mockResult?.version}`
        : undefined;

  return (
    <AppDialog
      wide
      title={`На дисплей: ${title}`}
      confirmText={sent ? "Готово" : send.busy ? "Отправляю…" : `Отправить${selected.length > 1 ? ` (${selected.length})` : ""}`}
      confirmDisabled={!sent && (selected.length === 0 || send.busy || !!previewError)}
      onConfirm={sent ? onClose : submit}
      onCancel={onClose}
    >
      <div className={`display-preview${(preview?.width ?? 792) > (preview?.height ?? 272) ? " landscape" : ""}`}>
        <DisplayMock
          png={preview?.png ?? null}
          width={preview?.width ?? 792}
          height={preview?.height ?? 272}
          state={mockProgress?.state ?? "draft"}
          caption={mockDisplay ? `${mockDisplay.id} · ${mockDisplay.name}` : undefined}
          note={!preview ? (previewError ? "нет предпросмотра" : "готовлю кадр…") : mockNote}
        />
        <div className="display-pick">
          {preview && !sent && (
            <p className="hint-text">
              {preview.width}×{preview.height}, QR версии {preview.qrVersion}: {preview.modules} модулей, {preview.scale} px на модуль. Та же строка QR, что для
              печати.
            </p>
          )}
          {warning && !sent && <div className="login-error">{warning}</div>}
          {previewError && <div className="login-error">{previewError}</div>}
          {listError && <div className="login-error">{listError}</div>}
          {displays && usable.length === 0 && <EmptyState>нет включённых дисплеев — добавьте на экране «Локации»</EmptyState>}
          {!sent &&
            usable.map((d) => (
              <label key={d.id}>
                <input type="checkbox" checked={selected.includes(d.id)} onChange={() => toggle(d.id)} />
                <span className="mono">{d.id}</span> {d.name}
                <StatusBadge status={d.status} />
              </label>
            ))}
          {sent &&
            sent.results.map((r) => {
              const d = displays?.find((x) => x.id === r.displayId);
              const p = pushProgress(r, d);
              return (
                <button
                  type="button"
                  key={r.displayId}
                  className={`push-row${r.displayId === mockId ? " push-row-focus" : ""}`}
                  onClick={() => setFocus(r.displayId)}
                  aria-pressed={r.displayId === mockId}
                >
                  <span className="display-card-head">
                    <span className="mono">{r.displayId}</span>
                    {d && <span>{d.name}</span>}
                    <Badge tone={PUSH_TONE[p.state]}>{p.text}</Badge>
                  </span>
                  {p.push ? <PushSteps phase={p.state === "shown" ? "DISPLAYED" : p.push.phase} failedAt={p.push.failedAt} /> : null}
                </button>
              );
            })}
          {send.error && <div className="login-error">{send.error}</div>}
        </div>
      </div>
    </AppDialog>
  );
}
