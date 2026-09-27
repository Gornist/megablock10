import { useEffect, useState } from "react";
import { api, ApiError } from "../../api/client";
import type { DisplayItem, DisplayPreview, DisplayPushResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppDialog, Badge, EmptyState } from "../../design/components";
import { pushProgress, scaleWarning, STATUS_LABEL, STATUS_TONE, type DisplaySource } from "./displayUtil";

const POLL_PUSH_MS = 1500;

/**
 * «Отправить на дисплей»: выбрать один или несколько дисплеев → предпросмотр кадра (ровно то, что уйдёт на e-paper) → отправить →
 * по каждому видно «отправляется / показан / ошибка». Картинку рисует сервер, браузер к дисплеям не ходит.
 */
export function DisplayPushDialog({ source, title, onClose }: { source: DisplaySource; title: string; onClose: () => void }) {
  const { data: displays, error: listError } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_PUSH_MS });
  const [selected, setSelected] = useState<string[]>([]);
  const [preview, setPreview] = useState<DisplayPreview | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [sent, setSent] = useState<DisplayPushResponse | null>(null);
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
      .post<DisplayPreview>("/api/displays/preview", { source, displayId: sizeOf })
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
    const res = await send.run(() => api.post<DisplayPushResponse>("/api/displays/push", { displayIds: selected, source }));
    if (res.ok) setSent(res.value);
  }

  const warning = preview ? scaleWarning(preview.scale) : null;

  return (
    <AppDialog
      wide
      title={`На дисплей: ${title}`}
      confirmText={sent ? "Готово" : send.busy ? "Отправляю…" : `Отправить${selected.length > 1 ? ` (${selected.length})` : ""}`}
      confirmDisabled={!sent && (selected.length === 0 || send.busy || !!previewError)}
      onConfirm={sent ? onClose : submit}
      onCancel={onClose}
    >
      <div className="display-preview">
        {preview ? (
          <img src={preview.png} alt="кадр для дисплея" />
        ) : (
          <EmptyState>{previewError ? "нет предпросмотра" : "готовлю кадр…"}</EmptyState>
        )}
        <div className="display-pick">
          {preview && (
            <p className="hint-text">
              {preview.width}×{preview.height}, QR версии {preview.qrVersion}: {preview.modules} модулей, {preview.scale} px на модуль. Та же строка QR, что для печати.
            </p>
          )}
          {warning && <div className="login-error">{warning}</div>}
          {previewError && <div className="login-error">{previewError}</div>}
          {listError && <div className="login-error">{listError}</div>}
          {displays && usable.length === 0 && <EmptyState>нет включённых дисплеев — добавьте на вкладке «Дисплеи»</EmptyState>}
          {!sent &&
            usable.map((d) => (
              <label key={d.id}>
                <input type="checkbox" checked={selected.includes(d.id)} onChange={() => toggle(d.id)} />
                <span className="mono">{d.id}</span> {d.name}
                <Badge tone={STATUS_TONE[d.status]}>{STATUS_LABEL[d.status]}</Badge>
              </label>
            ))}
          {sent &&
            sent.results.map((r) => {
              const p = pushProgress(r, displays?.find((d) => d.id === r.displayId));
              return (
                <div key={r.displayId} className="display-card-head">
                  <span className="mono">{r.displayId}</span>
                  <Badge tone={p.state === "shown" ? "ok" : p.state === "failed" ? "danger" : p.state === "sending" ? "accent" : "neutral"}>{p.text}</Badge>
                </div>
              );
            })}
          {send.error && <div className="login-error">{send.error}</div>}
        </div>
      </div>
    </AppDialog>
  );
}
