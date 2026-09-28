import { useState } from "react";
import { api } from "../../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem, DisplaySecretResponse, NodeSummary } from "../../api/types";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppSelect, Badge } from "../../design/components";
import { DeviceDetail } from "../displays/DeviceDetail";
import { DisplayForm, SecretPanel } from "../displays/DisplayForm";
import { STATUS_LABEL, STATUS_TONE } from "../displays/displayUtil";

/**
 * Точка узла — узел-контейнер в мире и есть QR-дисплей со звуком (владелец). Секция карточки узла: та же канонiчная
 * карточка (`DeviceDetail`), что на «Устройствах» и «Локациях» — полный набор команд обслуживания доступен и здесь,
 * не только на «Локациях». Узел без точки — «Привязать точку» из непривязанных.
 */
export function NodePoint({ nodeId }: { nodeId: string }) {
  const { data: displays, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_RELAXED_MS });
  const { data: channels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const { data: nodes } = useApiData<NodeSummary[]>("/api/nodes", { pollMs: POLL_RELAXED_MS });
  const point = (displays ?? []).find((d) => d.nodeId === nodeId);
  const [editing, setEditing] = useState(false);
  const [secret, setSecret] = useState<DisplaySecretResponse | null>(null);
  const takenNodes = new Map((displays ?? []).filter((d) => d.nodeId).map((d) => [d.nodeId!, d.id]));
  const namedNodes = (nodes ?? []).map((n) => ({ id: n.id, name: n.name }));
  if (!displays) return null;
  return (
    <section className="node-point" aria-label="точка узла">
      <div className="status-caps sound-step">Точка</div>
      {point ? (
        <DeviceDetail
          display={point}
          groups={groups ?? []}
          channels={channels ?? []}
          nodes={namedNodes}
          takenNodes={takenNodes}
          onChanged={reload}
          onEdit={() => setEditing(true)}
          onSecret={(r) => {
            setSecret(r);
            reload();
          }}
        />
      ) : (
        <BindPoint nodeId={nodeId} free={displays.filter((d) => !d.nodeId)} onChanged={reload} />
      )}
      {secret && <SecretPanel result={secret} onClose={() => setSecret(null)} />}
      {editing && point && (
        <DisplayForm
          editing={point}
          groups={groups ?? []}
          nodes={namedNodes}
          takenNodes={takenNodes}
          onCreated={() => setEditing(false)}
          onSaved={() => {
            setEditing(false);
            reload();
          }}
          onCancel={() => setEditing(false)}
        />
      )}
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
