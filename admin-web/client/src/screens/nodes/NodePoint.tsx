import { useState } from "react";
import { api } from "../../api/client";
import type { DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppSelect, Badge } from "../../design/components";
import { DeviceDetail } from "../displays/DeviceDetail";
import { STATUS_LABEL, STATUS_TONE } from "../displays/displayUtil";
import { useDeviceData } from "../displays/useDeviceData";
import { useDeviceEditor } from "../displays/useDeviceEditor";

/**
 * Точка узла — узел-контейнер в мире и есть QR-дисплей со звуком (владелец). Секция карточки узла: та же каноничная
 * карточка (`DeviceDetail`), что на «Устройствах» и «Локациях» — полный набор команд обслуживания доступен и здесь,
 * не только на «Локациях». Узел без точки — «Привязать точку» из непривязанных.
 */
export function NodePoint({ nodeId }: { nodeId: string }) {
  const data = useDeviceData();
  const { displays, reload } = data;
  // Как и раньше, здесь перечитываются только точки: список локаций от правки точки не меняется.
  const editor = useDeviceEditor(data, { reloadAfterSave: reload, reloadAfterChange: reload });
  const point = (displays ?? []).find((d) => d.nodeId === nodeId);
  if (!displays) return null;
  return (
    <section className="node-point" aria-label="точка узла">
      <div className="status-caps sound-step">Точка</div>
      {point ? (
        <DeviceDetail display={point} {...editor.detailProps(point)} />
      ) : (
        <BindPoint nodeId={nodeId} free={displays.filter((d) => !d.nodeId)} onChanged={reload} />
      )}
      {editor.secretPanel}
      {point && editor.formPanel}
    </section>
  );
}

function BindPoint({ nodeId, free, onChanged }: { nodeId: string; free: DisplayItem[]; onChanged: () => void }) {
  const [choice, setChoice] = useState("");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось привязать" });
  async function bind() {
    const r = await run(() => api.put(`/api/displays/${encodeURIComponent(choice)}/node`, { nodeId }));
    if (r.ok) onChanged();
  }
  return (
    <div className="node-point-empty">
      <p className="hint-text">У узла нет точки — QR только на бумаге, звука нет.</p>
      {free.length === 0 ? (
        <p className="hint-text">Свободных точек нет — добавьте на экране «Локации».</p>
      ) : (
        <div className="display-actions">
          <AppSelect value={choice} onChange={(e) => setChoice(e.target.value)} aria-label="точка для узла">
            <option value="">выберите точку…</option>
            {free.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name} ({d.id})
              </option>
            ))}
          </AppSelect>
          <AppButton variant="primary" onClick={bind} disabled={busy || !choice}>
            Привязать точку
          </AppButton>
        </div>
      )}
      {error && <div className="login-error">{error}</div>}
    </div>
  );
}

/** Значки точки в списке узлов: на связи ли, батарея, звук. Нет точки — прочерк. */
export function PointBadges({ point }: { point: DisplayItem | undefined }) {
  if (!point) return <span className="hint-text">—</span>;
  return (
    <span className="point-badges" data-point={point.id}>
      <Badge tone={STATUS_TONE[point.status]}>{STATUS_LABEL[point.status]}</Badge>
      {point.batteryPct !== null && (
        <span className={`hint-text mono${point.battery === "CRITICAL" ? " login-error" : ""}`} title="батарея">
          {point.batteryPct}%
        </span>
      )}
      {point.audio && <span title="звуковая точка">♪</span>}
    </span>
  );
}
